import 'package:convoze/core/db/database.dart';
import 'package:convoze/features/conversations/data/chat_message_view.dart';
import 'package:flutter_test/flutter_test.dart';

const me = 'user-me';
const other = 'user-other';
const conversationId = 'conv-1';

Message message({
  required String id,
  String senderId = me,
  DateTime? createdAt,
  bool isDeleted = false,
  String? clientMsgId,
}) => Message(
  id: id,
  conversationId: conversationId,
  senderId: senderId,
  clientMsgId: clientMsgId,
  type: 'text',
  content: isDeleted ? null : 'hi',
  reactions: '[]',
  isDeleted: isDeleted,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
);

OutboxData outbox({
  required String clientMsgId,
  String status = 'pending',
  DateTime? createdAt,
}) => OutboxData(
  clientMsgId: clientMsgId,
  conversationId: conversationId,
  content: 'draft',
  status: status,
  retryCount: 0,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
);

Participant participant({
  String userId = other,
  String? lastReadMessageId,
  String? lastDeliveredMessageId,
}) => Participant(
  conversationId: conversationId,
  userId: userId,
  role: 'member',
  lastReadMessageId: lastReadMessageId,
  lastDeliveredMessageId: lastDeliveredMessageId,
);

void main() {
  group('buildChatMessageViews', () {
    test('an incoming message has no tick', () {
      final views = buildChatMessageViews(
        messages: [message(id: 'm1', senderId: other)],
        outbox: const [],
        otherParticipants: [participant()],
        myUserId: me,
        isDirect: true,
      );
      expect(views.single.fromMe, isFalse);
      expect(views.single.tick, isNull);
    });

    test(
      'a confirmed direct message is "sent" until a watermark reaches it',
      () {
        final views = buildChatMessageViews(
          messages: [message(id: 'm1')],
          outbox: const [],
          otherParticipants: [participant()],
          myUserId: me,
          isDirect: true,
        );
        expect(views.single.tick, MessageTick.sent);
      },
    );

    test('"delivered" once the other participant\'s delivery watermark reaches it', () {
      final views = buildChatMessageViews(
        messages: [message(id: 'm1')],
        outbox: const [],
        otherParticipants: [participant(lastDeliveredMessageId: 'm1')],
        myUserId: me,
        isDirect: true,
      );
      expect(views.single.tick, MessageTick.delivered);
    });

    test('"read" once the other participant\'s read watermark reaches it', () {
      final views = buildChatMessageViews(
        messages: [message(id: 'm1')],
        outbox: const [],
        otherParticipants: [
          participant(lastReadMessageId: 'm1', lastDeliveredMessageId: 'm1'),
        ],
        myUserId: me,
        isDirect: true,
      );
      expect(views.single.tick, MessageTick.read);
    });

    test('a watermark ahead of this message still counts (>=, not ==)', () {
      final views = buildChatMessageViews(
        messages: [message(id: 'm1')],
        outbox: const [],
        otherParticipants: [participant(lastReadMessageId: 'm2')],
        myUserId: me,
        isDirect: true,
      );
      expect(views.single.tick, MessageTick.read);
    });

    test('a deleted message of mine has no tick', () {
      final views = buildChatMessageViews(
        messages: [message(id: 'm1', isDeleted: true)],
        outbox: const [],
        otherParticipants: [participant(lastReadMessageId: 'm1')],
        myUserId: me,
        isDirect: true,
      );
      expect(views.single.tick, isNull);
    });

    test('group messages only ever show "sent", never delivered/read', () {
      final views = buildChatMessageViews(
        messages: [message(id: 'm1')],
        outbox: const [],
        otherParticipants: [participant(lastReadMessageId: 'm1')],
        myUserId: me,
        isDirect: false,
      );
      expect(views.single.tick, MessageTick.sent);
    });

    test('an outbox row is "clock" while pending, "failed" once failed', () {
      final pending = buildChatMessageViews(
        messages: const [],
        outbox: [outbox(clientMsgId: 'c1')],
        otherParticipants: const [],
        myUserId: me,
        isDirect: true,
      );
      expect(pending.single.tick, MessageTick.clock);

      final failed = buildChatMessageViews(
        messages: const [],
        outbox: [outbox(clientMsgId: 'c1', status: 'failed')],
        otherParticipants: const [],
        myUserId: me,
        isDirect: true,
      );
      expect(failed.single.tick, MessageTick.failed);
    });

    test('confirmed messages sort by createdAt then id, outbox rows sort below all of them', () {
      final views = buildChatMessageViews(
        messages: [
          message(id: 'm2', createdAt: DateTime.utc(2026, 1, 1, 0, 0, 1)),
          message(id: 'm1', createdAt: DateTime.utc(2026, 1, 1)),
        ],
        outbox: [
          outbox(clientMsgId: 'c2', createdAt: DateTime.utc(2026, 1, 1, 0, 0, 3)),
          outbox(clientMsgId: 'c1', createdAt: DateTime.utc(2026, 1, 1, 0, 0, 2)),
        ],
        otherParticipants: [participant()],
        myUserId: me,
        isDirect: true,
      );
      expect(views.map((v) => v.id), ['m1', 'm2', 'c1', 'c2']);
    });

    test('same createdAt breaks the tie by id', () {
      final same = DateTime.utc(2026, 1, 1);
      final views = buildChatMessageViews(
        messages: [
          message(id: 'm-b', createdAt: same),
          message(id: 'm-a', createdAt: same),
        ],
        outbox: const [],
        otherParticipants: [participant()],
        myUserId: me,
        isDirect: true,
      );
      expect(views.map((v) => v.id), ['m-a', 'm-b']);
    });
  });
}
