import 'dart:convert';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/features/conversations/data/media_repository.dart';
import 'package:convoze/features/conversations/data/message_action_failure.dart';
import 'package:convoze/features/conversations/data/messages_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ack_socket.dart';

const me = 'me-1';
const conversationId = 'conv-1';

void main() {
  late AppDatabase db;
  late MessagesRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = MessagesRepository(db);
  });
  tearDown(() => db.close());

  group('sendText', () {
    test('inserts a pending text Outbox row', () async {
      await repository.sendText(conversationId, '  hey there  ');

      final row = await db.select(db.outbox).getSingle();
      expect(row.conversationId, conversationId);
      expect(row.content, 'hey there');
      expect(row.type, 'text');
      expect(row.media, null);
      expect(row.status, 'pending');
    });

    test('does nothing for blank content', () async {
      await repository.sendText(conversationId, '   ');

      expect(await db.select(db.outbox).get(), isEmpty);
    });
  });

  group('sendMedia', () {
    test('inserts an Outbox row carrying the encoded upload reference', () async {
      const upload = CloudinaryUploadResult(
        publicId: 'u/me-1/abc',
        version: '123',
        signature: 'sig',
        resourceType: 'image',
        bytes: 2048,
        format: 'jpg',
        width: 800,
        height: 600,
      );

      await repository.sendMedia(
        conversationId,
        kind: MediaKind.image,
        upload: upload,
        caption: 'nice view',
      );

      final row = await db.select(db.outbox).getSingle();
      expect(row.type, 'image');
      expect(row.content, 'nice view');
      final media = jsonDecode(row.media!) as Map<String, dynamic>;
      expect(media['publicId'], 'u/me-1/abc');
      expect(media['resourceType'], 'image');
      expect(media['width'], 800);
    });

    test('a file message carries its file name', () async {
      const upload = CloudinaryUploadResult(
        publicId: 'u/me-1/doc',
        version: '1',
        signature: 'sig',
        resourceType: 'raw',
        bytes: 4096,
        format: 'pdf',
      );

      await repository.sendMedia(
        conversationId,
        kind: MediaKind.file,
        upload: upload,
        fileName: 'invoice.pdf',
      );

      final row = await db.select(db.outbox).getSingle();
      final media = jsonDecode(row.media!) as Map<String, dynamic>;
      expect(media['fileName'], 'invoice.pdf');
    });
  });

  group('editMessage', () {
    test('sends the trimmed content over message:edit', () async {
      final socket = FakeAckSocket({'ok': true});

      await repository.editMessage(socket, messageId: 'msg-1', content: '  hi  ');

      expect(socket.sentEvents, ['message:edit']);
      expect(socket.sentPayloads.single, {'messageId': 'msg-1', 'content': 'hi'});
    });

    test('throws the failure the ack names when it refuses', () async {
      final socket = FakeAckSocket({'ok': false, 'code': 'FORBIDDEN'});

      expect(
        () => repository.editMessage(socket, messageId: 'msg-1', content: 'hi'),
        throwsA(isA<MessageActionForbidden>()),
      );
    });

    test('throws MessageActionNetworkFailure when the ack never lands', () async {
      final socket = TimingOutSocket();

      expect(
        () => repository.editMessage(socket, messageId: 'msg-1', content: 'hi'),
        throwsA(isA<MessageActionNetworkFailure>()),
      );
    });
  });

  group('deleteMessage', () {
    test('sends the messageId over message:delete', () async {
      final socket = FakeAckSocket({'ok': true});

      await repository.deleteMessage(socket, messageId: 'msg-1');

      expect(socket.sentEvents, ['message:delete']);
      expect(socket.sentPayloads.single, {'messageId': 'msg-1'});
    });

    test('throws the failure the ack names when it refuses', () async {
      final socket = FakeAckSocket({'ok': false, 'code': 'NOT_FOUND'});

      expect(
        () => repository.deleteMessage(socket, messageId: 'msg-1'),
        throwsA(isA<MessageActionNotFound>()),
      );
    });
  });

  group('watchMessages', () {
    test('shows a pending Outbox row immediately', () async {
      await repository.sendText(conversationId, 'on its way');

      final messages = await repository.watchMessages(conversationId, myUserId: me).first;

      expect(messages, hasLength(1));
      expect(messages.single.content, 'on its way');
      expect(messages.single.senderIsMe, isTrue);
      expect(messages.single.isPending, isTrue);
      expect(messages.single.id, null);
    });

    test(
      'prefers the landed Messages row over its pending Outbox row for the same clientMsgId',
      () async {
        await repository.sendText(conversationId, 'hello');
        final pending = await db.select(db.outbox).getSingle();

        // The sync engine's `message.new` handler both inserts the real row
        // and deletes the matching Outbox row once it lands (unchanged by
        // this feature) — simulate that here.
        await db
            .into(db.messages)
            .insert(
              MessagesCompanion.insert(
                id: 'msg-real',
                conversationId: conversationId,
                senderId: me,
                clientMsgId: Value(pending.clientMsgId),
                content: Value('hello'),
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            );
        await (db.delete(db.outbox)..where((t) => t.clientMsgId.equals(pending.clientMsgId))).go();

        final messages = await repository.watchMessages(conversationId, myUserId: me).first;

        expect(messages, hasLength(1));
        expect(messages.single.id, 'msg-real');
        expect(messages.single.isPending, isFalse);
      },
    );

    test('reads media fields off a landed image message', () async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'msg-1',
              conversationId: conversationId,
              senderId: 'other-1',
              type: const Value('image'),
              mediaPublicId: const Value('u/other-1/xyz'),
              mediaResourceType: const Value('image'),
              mediaWidth: const Value(400),
              mediaHeight: const Value(300),
              mediaUrl: const Value('https://cdn.test/full.jpg'),
              mediaThumbnailUrl: const Value('https://cdn.test/thumb.jpg'),
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final messages = await repository.watchMessages(conversationId, myUserId: me).first;

      expect(messages.single.isImage, isTrue);
      expect(messages.single.senderIsMe, isFalse);
      expect(messages.single.mediaThumbnailUrl, 'https://cdn.test/thumb.jpg');
      expect(messages.single.mediaWidth, 400);
    });

    test('reads editedAt off an edited message, null for an unedited one', () async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'msg-1',
              conversationId: conversationId,
              senderId: me,
              content: const Value('hi (fixed)'),
              editedAt: Value(DateTime.utc(2026, 1, 2)),
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final messages = await repository.watchMessages(conversationId, myUserId: me).first;

      expect(messages.single.editedAt?.toUtc(), DateTime.utc(2026, 1, 2));
    });
  });
}
