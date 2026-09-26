import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../db/database.dart';
import '../db/database_provider.dart';
import '../network/dio_provider.dart';
import '../storage/token_store.dart';
import 'rest_snapshot.dart';
import 'wire.dart';

part 'sync_engine.g.dart';

/// The client half of ADR 0008/0009's delivery contract (#51): owns the
/// socket's `sync:*` handlers and the Outbox drainer (ADR 0009). Registered
/// on a socket once per connect via [attach] (`ConnectionManager`'s
/// `onSocketCreated` seam) and supplies the Sync cursor for every (re)connect
/// attempt via [readCursor] (its `readSyncCursor` seam).
class SyncEngine {
  SyncEngine({required this.db, required this.dio, required this.tokenStore});

  final AppDatabase db;
  final Dio dio;
  final TokenStore tokenStore;

  bool _resetting = false;
  bool _draining = false;
  bool _flushingReads = false;

  /// The stored Sync cursor, sent as `since` in the handshake `auth`
  /// payload. Null sends no `since` (a fresh install, or right after a wipe).
  Future<int?> readCursor() => db.readCursor();

  /// Registers this engine's handlers on [socket]. Call once per new socket
  /// instance — automatic reconnects reuse it, so this never needs to run
  /// again for the same socket (ADR 0009).
  void attach(io.Socket socket) {
    socket
      ..on('sync:batch', (args) => unawaited(_handleBatch(args)))
      ..on('sync:reset', (data) => unawaited(_handleReset(data, socket)))
      ..on('sync:caught-up', (_) => unawaited(_drainAndFlush(socket)))
      ..onConnect((_) => unawaited(_drainAndFlush(socket)));
  }

  Future<void> _drainAndFlush(io.Socket socket) async {
    unawaited(drainOutbox(socket));
    unawaited(flushPendingReads(socket));
  }

  // --- sync:batch --------------------------------------------------------

  /// `args` is `[payload, ackFn]` — the server sent this with
  /// `emitWithAck`, so the client must call `ackFn` (see `pump.js`).
  Future<void> _handleBatch(dynamic args) async {
    final list = args as List;
    final payload = (list[0] as Map).cast<String, dynamic>();
    final ackFn = list[1] as Function;
    ackFn(await applyBatch(payload));
  }

  /// Applies one `sync:batch` payload (`{updates, users}`) in a single drift
  /// transaction and returns the seq to ack with (ADR 0008: only after
  /// commit). Exposed directly (rather than only through [_handleBatch]) so
  /// it can be tested without a real socket.
  Future<int> applyBatch(Map<String, dynamic> payload) async {
    final updates = ((payload['updates'] as List?) ?? const [])
        .map((u) => (u as Map).cast<String, dynamic>())
        .toList();
    final myUserId = (await tokenStore.readUser())?.id;

    int? highestApplied;
    await db.transaction(() async {
      await upsertUsers(db, (payload['users'] as List?) ?? const []);
      final cursor = await db.readCursor() ?? -1;
      for (final update in updates) {
        final seq = update['seq'] as int;
        if (seq <= cursor) continue;
        await _applyOne(update, myUserId: myUserId);
        highestApplied = seq;
      }
      if (highestApplied != null) await db.writeCursor(highestApplied!);
    });

    // A retried/overlapping batch whose rows were all already applied still
    // needs an ack so the pump can advance past it.
    return highestApplied ?? await db.readCursor() ?? 0;
  }

  Future<void> _applyOne(Map<String, dynamic> update, {required String? myUserId}) async {
    final kind = update['kind'] as String;
    final payload = (update['payload'] as Map).cast<String, dynamic>();
    switch (kind) {
      case 'message.new':
        await upsertMessagePayload(db, payload);
        final senderId = payload['senderId'] as String?;
        if (senderId != null && senderId != myUserId && payload['isDeleted'] != true) {
          await _incrementUnread(payload['conversationId'] as String);
        }
        // The sender's own Device sees its just-sent Message drain back to
        // it (ADR 0008); a matching Outbox row means the drainer's own
        // post-ack delete (below) hasn't run yet — a no-op here beyond this
        // cleanup, since the Message row itself is written the same way
        // either way.
        final clientMsgId = payload['clientMsgId'] as String?;
        if (clientMsgId != null) {
          await (db.delete(db.outbox)..where((t) => t.clientMsgId.equals(clientMsgId))).go();
        }
      case 'message.edited':
      case 'message.deleted':
        await upsertMessagePayload(db, payload);
      case 'reaction.changed':
        await _applyReaction(payload);
      case 'conversation.receipts':
        await _applyReceipts(payload);
      case 'conversation.joined':
        await _applyConversationJoined(payload, myUserId: myUserId);
      case 'conversation.prefs':
        await applyConversationPrefs(db, payload);
      default:
        // Forward-compatible: `conversation.left`/`members`/`prefs` are
        // later specs' job (ADR 0008's own hydrator doesn't emit them yet
        // either) — skip rather than fail the whole batch.
        break;
    }
  }

  Future<void> _incrementUnread(String conversationId) {
    return db.customStatement(
      'UPDATE conversations SET unread_count = unread_count + 1 WHERE id = ?',
      [conversationId],
    );
  }

  Future<void> _applyReaction(Map<String, dynamic> payload) {
    final messageId = payload['messageId'] as String;
    final reactions = (payload['reactions'] as List).cast<Map<String, dynamic>>();
    return (db.update(db.messages)..where((t) => t.id.equals(messageId))).write(
      MessagesCompanion(reactions: Value(jsonEncode(reactions))),
    );
  }

  Future<void> _applyReceipts(Map<String, dynamic> payload) async {
    final conversationId = payload['conversationId'] as String;
    for (final raw in (payload['participants'] as List)) {
      final p = (raw as Map).cast<String, dynamic>();
      await (db.update(db.participants)..where(
            (t) => t.conversationId.equals(conversationId) & t.userId.equals(p['userId'] as String),
          ))
          .write(
            ParticipantsCompanion(
              lastReadMessageId: Value(p['lastReadMessageId'] as String?),
              lastDeliveredMessageId: Value(p['lastDeliveredMessageId'] as String?),
            ),
          );
    }
    final unreadCount = payload['unreadCount'] as int;
    await (db.update(db.conversations)..where((t) => t.id.equals(conversationId))).write(
      ConversationsCompanion(unreadCount: Value(unreadCount)),
    );
  }

  /// The backend's `conversation.joined` hydration is just the bare
  /// Conversation row (`{...conversationById.get(...)}` in
  /// `backend/src/messaging/hydrator.js`) — no participants, no
  /// `unreadCount`, unlike ADR 0009's description of it. Today this Update
  /// only ever fires for a brand-new direct Conversation (`directConversation.js`),
  /// so both are safe defaults: 0 unread (nothing's been sent yet), and the
  /// two Participants are `me` plus `createdById` (there's no third
  /// possibility in a direct Conversation). Group membership Updates
  /// (`conversation.members`) aren't implemented backend-side yet.
  Future<void> _applyConversationJoined(
    Map<String, dynamic> payload, {
    required String? myUserId,
  }) async {
    final id = payload['id'] as String;
    final existing = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: id,
              type: payload['type'] as String,
              name: Value(payload['name'] as String?),
              createdById: Value(payload['createdById'] as String?),
              createdAt: Value(DateTime.parse(payload['createdAt'] as String)),
            ),
          );
    }
    if (myUserId != null) await _upsertParticipant(conversationId: id, userId: myUserId);
    final createdById = payload['createdById'] as String?;
    if (payload['type'] == 'direct' && createdById != null && createdById != myUserId) {
      await _upsertParticipant(conversationId: id, userId: createdById);
    }
  }

  Future<void> _upsertParticipant({required String conversationId, required String userId}) {
    return db
        .into(db.participants)
        .insertOnConflictUpdate(
          ParticipantsCompanion.insert(conversationId: conversationId, userId: userId),
        );
  }

  // --- sync:reset ----------------------------------------------------------

  Future<void> _handleReset(dynamic data, io.Socket socket) async {
    final payload = (data as Map).cast<String, dynamic>();
    final currentSeq = payload['currentSeq'] as int;
    if (_resetting) return;
    _resetting = true;
    try {
      await db.wipeExceptOutbox();
      await rebuildSnapshotFromRest(dio: dio, db: db, currentSeq: currentSeq);
    } finally {
      _resetting = false;
    }
    unawaited(drainOutbox(socket));
  }

  // --- Outbox drainer --------------------------------------------------

  /// One serial FIFO drain across every Conversation (ADR 0009), run
  /// whenever the socket (re)connects or catches up. Populated by
  /// `MessagesRepository.sendText`/`sendMedia`.
  Future<void> drainOutbox(io.Socket socket) async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final next =
            await (db.select(db.outbox)
                  ..where((t) => t.status.equals('pending'))
                  ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (next == null) return;

        Map<String, dynamic>? response;
        try {
          response = ((await socket.timeout(15000).emitWithAckAsync('message:send', {
            'clientMsgId': next.clientMsgId,
            'conversationId': next.conversationId,
            'content': next.content,
            'type': next.type,
            if (next.replyToMessageId != null) 'replyToMessageId': next.replyToMessageId,
            if (next.linkPreview != null) 'linkPreview': jsonDecode(next.linkPreview!),
            if (next.media != null) 'media': jsonDecode(next.media!),
          })) as Map).cast<String, dynamic>();
        } catch (_) {
          // Ack timed out or the socket dropped mid-send: stop, don't spin.
          // The next connect (or `sync:caught-up`) resumes the drain.
          return;
        }

        if (response['ok'] == true) {
          await (db.delete(db.outbox)..where((t) => t.clientMsgId.equals(next.clientMsgId))).go();
          continue;
        }

        if (response['code'] == 'RATE_LIMITED') {
          final retryCount = next.retryCount + 1;
          await (db.update(db.outbox)..where((t) => t.clientMsgId.equals(next.clientMsgId))).write(
            OutboxCompanion(retryCount: Value(retryCount)),
          );
          await Future<void>.delayed(Duration(seconds: min(30, 1 << retryCount)));
          continue;
        }

        await (db.update(db.outbox)..where((t) => t.clientMsgId.equals(next.clientMsgId))).write(
          const OutboxCompanion(status: Value('failed')),
        );
      }
    } finally {
      _draining = false;
    }
  }

  // --- Pending reads flusher ---------------------------------------------

  /// Sends every queued read-watermark move as `conversation:read` (#53,
  /// ADR 0009: "flushed as `conversation:read` when connected and deleted on
  /// ack"), whenever the socket (re)connects or catches up — the same shape
  /// as [drainOutbox], one row at a time, stopping (rather than spinning) on
  /// a timeout or dropped socket so the next connect resumes it.
  Future<void> flushPendingReads(io.Socket socket) async {
    if (_flushingReads) return;
    _flushingReads = true;
    try {
      while (true) {
        final next = await (db.select(
          db.pendingReads,
        )..limit(1)).getSingleOrNull();
        if (next == null) return;

        Map<String, dynamic>? response;
        try {
          response =
              ((await socket.timeout(15000).emitWithAckAsync('conversation:read', {
                        'conversationId': next.conversationId,
                        'messageId': next.messageId,
                      }))
                      as Map)
                  .cast<String, dynamic>();
        } catch (_) {
          return;
        }

        if (response['ok'] == true) {
          await (db.delete(db.pendingReads)..where(
                (t) => t.conversationId.equals(next.conversationId),
              ))
              .go();
          continue;
        }

        // Not retryable in place (unlike the Outbox's `RATE_LIMITED`): an
        // error here means the read itself was rejected (e.g. the Message
        // no longer exists). Drop it rather than spin forever on it — a
        // later read for the same Conversation will replace it anyway.
        await (db.delete(
          db.pendingReads,
        )..where((t) => t.conversationId.equals(next.conversationId))).go();
      }
    } finally {
      _flushingReads = false;
    }
  }
}

@Riverpod(keepAlive: true)
SyncEngine syncEngine(Ref ref) => SyncEngine(
  db: ref.watch(appDatabaseProvider),
  dio: ref.watch(dioProvider),
  tokenStore: ref.watch(tokenStoreProvider),
);
