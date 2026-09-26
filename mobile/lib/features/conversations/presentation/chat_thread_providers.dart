import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/formatting/display_name.dart';
import '../../../core/storage/token_store.dart';
import '../data/chat_message_view.dart';
import '../data/messages_repository.dart';

part 'chat_thread_providers.g.dart';

// The five providers below are hand-written rather than `@riverpod`
// generated: `riverpod_generator` can't emit code for a provider whose
// return type is a drift-generated `DataClass` (`Message`, `Conversation`,
// `Participant`, `LocalUser` all hit `InvalidTypeException: The type is
// invalid and cannot be converted to code` — confirmed in isolation,
// unrelated to naming/privacy). Everything downstream of these, whose
// return types are this feature's own classes, uses `@riverpod` as usual.

final _confirmedMessagesProvider = StreamProvider.family<List<Message>, String>(
  (ref, conversationId) =>
      ref.watch(messagesRepositoryProvider).watchConfirmedMessages(conversationId),
);

final _outboxRowsProvider = StreamProvider.family<List<OutboxData>, String>(
  (ref, conversationId) =>
      ref.watch(messagesRepositoryProvider).watchOutbox(conversationId),
);

final _otherParticipantsProvider = StreamProvider.family<List<Participant>, String>(
  (ref, conversationId) =>
      ref.watch(messagesRepositoryProvider).watchOtherParticipants(conversationId),
);

final _conversationRowProvider = StreamProvider.family<Conversation?, String>((
  ref,
  conversationId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.conversations,
  )..where((t) => t.id.equals(conversationId))).watchSingleOrNull();
});

final _localUserProvider = StreamProvider.family<LocalUser?, String>((ref, userId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.users,
  )..where((t) => t.id.equals(userId))).watchSingleOrNull();
});

/// The chat screen's merged, tick-derived message list (#53/#55):
/// recombines whenever any of the three underlying replica streams change —
/// Riverpod's own dependency tracking doing the work an explicit
/// `combineLatest` would elsewhere.
@riverpod
Future<List<ChatMessageView>> chatMessages(
  Ref ref,
  String conversationId,
) async {
  final messages = await ref.watch(_confirmedMessagesProvider(conversationId).future);
  final outbox = await ref.watch(_outboxRowsProvider(conversationId).future);
  final others = await ref.watch(_otherParticipantsProvider(conversationId).future);
  final conversation = await ref.watch(_conversationRowProvider(conversationId).future);
  final myId = (await ref.watch(tokenStoreProvider).readUser())?.id ?? '';
  return buildChatMessageViews(
    messages: messages,
    outbox: outbox,
    otherParticipants: others,
    myUserId: myId,
    isDirect: conversation?.type == 'direct',
  );
}

/// The chat screen header's title: the other Participant's name for a
/// direct chat, the Conversation's name for a group.
@riverpod
Future<String> chatThreadTitle(Ref ref, String conversationId) async {
  final conversation = await ref.watch(_conversationRowProvider(conversationId).future);
  if (conversation == null) return '';
  if (conversation.type == 'group') return conversation.name ?? 'Group';

  final others = await ref.watch(_otherParticipantsProvider(conversationId).future);
  if (others.isEmpty) return '';
  final otherUser = await ref.watch(
    _localUserProvider(others.first.userId).future,
  );
  if (otherUser == null) return '';
  return displayName(
    displayName: otherUser.displayName,
    phoneNumber: otherUser.phoneNumber,
  );
}

class ChatThreadState {
  const ChatThreadState({this.isLoadingOlder = false, this.reachedStart = false});

  final bool isLoadingOlder;
  final bool reachedStart;

  ChatThreadState copyWith({bool? isLoadingOlder, bool? reachedStart}) =>
      ChatThreadState(
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        reachedStart: reachedStart ?? this.reachedStart,
      );
}

/// Owns the chat screen's history-paging state (#55): the initial "fetch
/// the first page if nothing's local yet" fetch and the scroll-to-top
/// trigger both go through [loadOlder], which is guarded against
/// concurrent/redundant calls.
@riverpod
class ChatThreadController extends _$ChatThreadController {
  @override
  ChatThreadState build(String conversationId) => const ChatThreadState();

  Future<void> ensureInitialPage() async {
    if (state.reachedStart) return;
    final hasLocal = await ref
        .read(messagesRepositoryProvider)
        .hasLocalMessages(conversationId);
    if (!hasLocal) await loadOlder();
  }

  Future<void> loadOlder() async {
    if (state.isLoadingOlder || state.reachedStart) return;
    state = state.copyWith(isLoadingOlder: true);
    try {
      final result = await ref
          .read(messagesRepositoryProvider)
          .loadOlder(conversationId);
      state = state.copyWith(
        isLoadingOlder: false,
        reachedStart: result.reachedStart,
      );
    } catch (_) {
      // A failed fetch (offline, server error) just leaves the trigger
      // ready to retry on the next scroll/frame — no error state to show,
      // matching how the rest of this screen degrades offline.
      state = state.copyWith(isLoadingOlder: false);
    }
  }
}
