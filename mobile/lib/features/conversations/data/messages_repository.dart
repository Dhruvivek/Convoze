import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import '../../../core/db/database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/realtime/connection_manager.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/wire.dart';

part 'messages_repository.g.dart';

/// The outcome of fetching one page of older history (#55).
class LoadOlderResult {
  const LoadOlderResult({required this.fetchedCount, required this.reachedStart});

  final int fetchedCount;

  /// True once the fetched page was shorter than a full page — the server's
  /// signal (`nextBefore: null`) that there's nothing older left.
  final bool reachedStart;
}

/// The chat screen's data layer (#53/#55): sending, marking read, and
/// paging history, all against the Local replica (`CONTEXT.md`) — the
/// screen itself never touches the socket or REST directly.
class MessagesRepository {
  MessagesRepository({
    required this.db,
    required this.dio,
    required this.tokenStore,
    required this.syncEngine,
    required this.currentSocket,
  });

  final AppDatabase db;
  final Dio dio;
  final TokenStore tokenStore;
  final SyncEngine syncEngine;

  /// The live socket, or null while there is none (`ConnectionManager.socket`)
  /// — kept to just this seam, rather than the whole connection manager, so
  /// [send]/[markRead] can kick an immediate drain/flush without depending
  /// on connection lifecycle/app-lifecycle plumbing that's irrelevant here.
  final io.Socket? Function() currentSocket;

  Stream<List<Message>> watchConfirmedMessages(String conversationId) =>
      (db.select(db.messages)
            ..where((t) => t.conversationId.equals(conversationId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch();

  Stream<List<OutboxData>> watchOutbox(String conversationId) =>
      (db.select(db.outbox)
            ..where((t) => t.conversationId.equals(conversationId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  /// Every other Participant's row (both watermarks), for tick derivation.
  Stream<List<Participant>> watchOtherParticipants(String conversationId) {
    return Stream.fromFuture(tokenStore.readUser()).asyncExpand((user) {
      final myId = user?.id;
      final query = db.select(db.participants)
        ..where((t) => t.conversationId.equals(conversationId));
      return query.watch().map(
        (rows) => rows.where((p) => p.userId != myId).toList(),
      );
    });
  }

  /// Whether any Message for [conversationId] is already in the replica —
  /// the chat screen's "fetch the first page on open" trigger (#55).
  Future<bool> hasLocalMessages(String conversationId) async {
    final row = await (db.select(db.messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Queues [text] in the Outbox (ADR 0009) and, if connected, kicks the
  /// drainer right away rather than waiting for the next reconnect.
  /// [linkPreview] is the `{url, title, description}` shape `drainOutbox`
  /// already knows how to send (`sendMessage.js` validates it server-side;
  /// nothing on this branch builds one yet, but the Outbox column and wire
  /// shape have carried it since #51).
  Future<void> send(
    String conversationId,
    String text, {
    String? replyToMessageId,
    Map<String, dynamic>? linkPreview,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientMsgId: const Uuid().v4(),
            conversationId: conversationId,
            content: trimmed,
            replyToMessageId: Value(replyToMessageId),
            linkPreview: Value(
              linkPreview == null ? null : jsonEncode(linkPreview),
            ),
            createdAt: DateTime.now().toUtc(),
          ),
        );
    final socket = currentSocket();
    if (socket != null) unawaited(syncEngine.drainOutbox(socket));
  }

  /// Puts a `failed` Outbox row ("failed — tap to retry or delete", ADR
  /// 0009) back to `pending` and, if connected, kicks the drainer right away
  /// rather than waiting for the next reconnect. A no-op if the row is
  /// already gone (sent meanwhile, or already discarded).
  Future<void> retry(String clientMsgId) async {
    await (db.update(db.outbox)..where((t) => t.clientMsgId.equals(clientMsgId)))
        .write(const OutboxCompanion(status: Value('pending')));
    final socket = currentSocket();
    if (socket != null) unawaited(syncEngine.drainOutbox(socket));
  }

  /// Deletes a `failed` Outbox row for good, per the user's "delete" choice
  /// (ADR 0009).
  Future<void> discard(String clientMsgId) {
    return (db.delete(
      db.outbox,
    )..where((t) => t.clientMsgId.equals(clientMsgId))).go();
  }

  /// Moves the local read watermark to the newest local Message at once,
  /// zeroes the unread badge, and upserts the one pending read this
  /// Conversation may have (ADR 0009) — flushed by [SyncEngine] when
  /// connected. A no-op if already caught up, or if nothing's local yet.
  Future<void> markRead(String conversationId) async {
    final myId = (await tokenStore.readUser())?.id;
    if (myId == null) return;
    final latest = await (db.select(db.messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) return;

    final me = await (db.select(db.participants)..where(
          (t) =>
              t.conversationId.equals(conversationId) & t.userId.equals(myId),
        ))
        .getSingleOrNull();
    if (me != null &&
        me.lastReadMessageId != null &&
        me.lastReadMessageId!.compareTo(latest.id) >= 0) {
      return;
    }

    await db.transaction(() async {
      await (db.update(db.participants)..where(
            (t) =>
                t.conversationId.equals(conversationId) &
                t.userId.equals(myId),
          ))
          .write(
            ParticipantsCompanion(
              lastReadMessageId: Value(latest.id),
              lastDeliveredMessageId: Value(latest.id),
            ),
          );
      await (db.update(
        db.conversations,
      )..where((t) => t.id.equals(conversationId))).write(
        const ConversationsCompanion(unreadCount: Value(0)),
      );
      await db
          .into(db.pendingReads)
          .insertOnConflictUpdate(
            PendingReadsCompanion.insert(
              conversationId: conversationId,
              messageId: latest.id,
            ),
          );
    });

    final socket = currentSocket();
    if (socket != null) unawaited(syncEngine.flushPendingReads(socket));
  }

  /// Fetches the page of history strictly older than the oldest local
  /// Message (or the first page, if none is local yet) and applies it to
  /// the replica (#55). Reuses `wire.dart`'s hydration helpers — the exact
  /// functions the sync engine and snapshot rebuild already use for the
  /// same wire shape.
  Future<LoadOlderResult> loadOlder(String conversationId) async {
    final oldest = await (db.select(db.messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();

    final response = await dio.get<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      queryParameters: {if (oldest != null) 'before': oldest.id},
    );
    final body = response.data!;
    final messages = (body['messages'] as List)
        .map((m) => (m as Map).cast<String, dynamic>())
        .toList();

    await db.transaction(() async {
      await upsertUsers(db, (body['users'] as List?) ?? const []);
      for (final message in messages) {
        await upsertMessagePayload(db, message);
      }
    });

    return LoadOlderResult(
      fetchedCount: messages.length,
      reachedStart: body['nextBefore'] == null,
    );
  }
}

@Riverpod(keepAlive: true)
MessagesRepository messagesRepository(Ref ref) => MessagesRepository(
  db: ref.watch(appDatabaseProvider),
  dio: ref.watch(dioProvider),
  tokenStore: ref.watch(tokenStoreProvider),
  syncEngine: ref.watch(syncEngineProvider),
  // Read lazily, not watched: a new socket instance shouldn't recreate this
  // keepAlive repository, the same trick `connectionManagerProvider` itself
  // uses for its own lazy reads.
  currentSocket: () => ref.read(connectionManagerProvider).socket,
);
