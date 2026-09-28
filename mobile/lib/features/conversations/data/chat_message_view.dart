import 'dart:convert';

import '../../../core/db/database.dart';

/// A `fromMe` Message's tick state (`CONTEXT.md`'s Read/Delivery watermark),
/// derived from the replica rather than stored per message (#53). An
/// incoming Message never has one.
enum MessageTick {
  /// Still in the Outbox, not yet acked.
  clock,

  /// The Outbox row failed and hasn't been retried.
  failed,

  /// Confirmed by the server; no other Participant has it yet.
  sent,

  /// At least one other Participant's delivery watermark has reached it.
  delivered,

  /// At least one other Participant's read watermark has reached it.
  read,
}

/// One reaction on a Message (#103), mirroring `reaction.changed`'s
/// hydration: `{userId, emoji}`.
class MessageReaction {
  const MessageReaction({required this.userId, required this.emoji});

  final String userId;
  final String emoji;
}

/// The quoted preview of a reply's original Message (#102), hydrated from
/// whatever's locally loaded — a self-join at query time (`tables.dart`),
/// never a stored column. Null on [ChatMessageView.replyPreview] while the
/// original isn't loaded locally, distinct from `replyToMessageId` being
/// null (no reply at all).
class ReplyPreview {
  const ReplyPreview({
    required this.fromMe,
    required this.isDeleted,
    required this.type,
    this.content,
    this.mediaFileName,
  });

  final bool fromMe;
  final bool isDeleted;
  final String type;
  final String? content;
  final String? mediaFileName;

  String get snippet => messageSnippet(
    isDeleted: isDeleted,
    type: type,
    content: content,
    mediaFileName: mediaFileName,
  );
}

/// A short one-line label for a Message, shared by [ReplyPreview] (the
/// quoted block on a reply) and the composer's "Replying to" banner, which
/// builds one straight from the live [ChatMessageView] being replied to.
String messageSnippet({
  required bool isDeleted,
  required String type,
  String? content,
  String? mediaFileName,
}) {
  if (isDeleted) return 'Original message was deleted';
  if (type == 'image') return (content?.isNotEmpty ?? false) ? content! : 'Photo';
  if (type == 'file') return mediaFileName ?? 'Document';
  return content ?? '';
}

/// One row in a chat thread — either a confirmed [Message] or a still-queued
/// Outbox entry — with its [tick] already derived, so the screen never
/// compares watermarks itself.
class ChatMessageView {
  const ChatMessageView({
    required this.id,
    this.clientMsgId,
    required this.senderId,
    required this.fromMe,
    required this.myUserId,
    required this.content,
    required this.type,
    required this.createdAt,
    required this.isDeleted,
    this.editedAt,
    this.tick,
    this.mediaUrl,
    this.mediaThumbnailUrl,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaFileName,
    this.mediaBytes,
    this.replyToMessageId,
    this.replyPreview,
    this.reactions = const [],
  });

  /// The Message id, or the Outbox row's `clientMsgId` while still pending
  /// (ADR 0009: "which is also the id a pending Message row uses locally
  /// until the real one arrives").
  final String id;

  final String? clientMsgId;
  final String senderId;
  final bool fromMe;

  /// The viewing User's own id — carried on every row so a bubble can tell
  /// whether *it* reacted with a given emoji without extra plumbing (#103).
  final String myUserId;
  final String? content;

  /// `'text'`, `'image'` or `'file'`.
  final String type;
  final DateTime createdAt;
  final bool isDeleted;

  /// Set once this Message has been edited (#56); null for a still-pending
  /// Outbox row, which is never edited before it lands.
  final DateTime? editedAt;

  /// Null for a Message from someone else, or a deleted Message of mine.
  final MessageTick? tick;

  /// Null while still pending (the upload hasn't landed a delivery URL yet)
  /// or for a text message.
  final String? mediaUrl;
  final String? mediaThumbnailUrl;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? mediaFileName;
  final int? mediaBytes;

  /// The Message this one replies to (`CONTEXT.md`'s Reply), or null (#102).
  final String? replyToMessageId;

  /// Hydrated from whatever's locally loaded; null while [replyToMessageId]
  /// is set but its target isn't (a reply into history not paged in yet).
  final ReplyPreview? replyPreview;

  /// The current reaction set (#103) — never a diff.
  final List<MessageReaction> reactions;

  bool get isImage => type == 'image';
  bool get isFile => type == 'file';

  /// Whether [myUserId] is among this Message's reactors for [emoji] — the
  /// bubble's "is my pill highlighted" check.
  bool reactedByMeWith(String emoji) =>
      reactions.any((r) => r.userId == myUserId && r.emoji == emoji);
}

/// Merges confirmed [messages] and pending [outbox] rows for one
/// conversation into one ordered, tick-derived view (#53's acceptance
/// criteria): confirmed messages ordered by server `createdAt` then `id`,
/// Outbox rows sorted below all of them in composed order (ADR 0009).
///
/// Tick derivation only applies to direct chats (`isDirect`): a group's
/// `fromMe` messages just show [MessageTick.sent] once confirmed, since
/// group delivery/read semantics aren't part of this ticket.
List<ChatMessageView> buildChatMessageViews({
  required List<Message> messages,
  required List<OutboxData> outbox,
  required List<Participant> otherParticipants,
  required String myUserId,
  required bool isDirect,
}) {
  final confirmed = [...messages]
    ..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  final pending = [...outbox]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final byId = {for (final m in confirmed) m.id: m};

  return [
    ...confirmed.map(
      (m) => ChatMessageView(
        id: m.id,
        clientMsgId: m.clientMsgId,
        senderId: m.senderId,
        fromMe: m.senderId == myUserId,
        myUserId: myUserId,
        content: m.content,
        type: m.type,
        createdAt: m.createdAt,
        isDeleted: m.isDeleted,
        editedAt: m.editedAt,
        tick: m.senderId == myUserId && !m.isDeleted
            ? _confirmedTick(
                messageId: m.id,
                otherParticipants: otherParticipants,
                isDirect: isDirect,
              )
            : null,
        mediaUrl: m.mediaUrl,
        mediaThumbnailUrl: m.mediaThumbnailUrl,
        mediaWidth: m.mediaWidth,
        mediaHeight: m.mediaHeight,
        mediaFileName: m.mediaFileName,
        mediaBytes: m.mediaBytes,
        replyToMessageId: m.replyToMessageId,
        replyPreview: _buildReplyPreview(m.replyToMessageId, byId, myUserId),
        reactions: _parseReactions(m.reactions),
      ),
    ),
    ...pending.map((o) => _pendingView(o, myUserId, byId)),
  ];
}

/// A pending Outbox row's view: its media fields (if any) come from the
/// JSON reference `MessagesRepository.sendMedia` queued (ADR 0009) — there's
/// no delivery URL yet, only what the upload itself reported, so
/// [ChatMessageView.mediaUrl]/[ChatMessageView.mediaThumbnailUrl] stay null
/// until the real Message lands. [byId] resolves its reply preview (#102)
/// the same way a confirmed Message's does — its `replyToMessageId` can only
/// point at an already-confirmed Message, never another pending row.
ChatMessageView _pendingView(
  OutboxData o,
  String myUserId,
  Map<String, Message> byId,
) {
  final media = o.media == null
      ? const <String, dynamic>{}
      : (jsonDecode(o.media!) as Map).cast<String, dynamic>();
  return ChatMessageView(
    id: o.clientMsgId,
    clientMsgId: o.clientMsgId,
    senderId: myUserId,
    fromMe: true,
    myUserId: myUserId,
    content: o.content,
    type: o.type,
    createdAt: o.createdAt,
    isDeleted: false,
    tick: o.status == 'failed' ? MessageTick.failed : MessageTick.clock,
    mediaWidth: media['width'] as int?,
    mediaHeight: media['height'] as int?,
    mediaFileName: media['fileName'] as String?,
    mediaBytes: media['bytes'] as int?,
    replyToMessageId: o.replyToMessageId,
    replyPreview: _buildReplyPreview(o.replyToMessageId, byId, myUserId),
  );
}

ReplyPreview? _buildReplyPreview(
  String? replyToMessageId,
  Map<String, Message> byId,
  String myUserId,
) {
  if (replyToMessageId == null) return null;
  final target = byId[replyToMessageId];
  if (target == null) return null;
  return ReplyPreview(
    fromMe: target.senderId == myUserId,
    isDeleted: target.isDeleted,
    type: target.type,
    content: target.content,
    mediaFileName: target.mediaFileName,
  );
}

List<MessageReaction> _parseReactions(String reactionsJson) {
  if (reactionsJson.isEmpty || reactionsJson == '[]') return const [];
  final list = jsonDecode(reactionsJson) as List;
  return list
      .map((r) => (r as Map).cast<String, dynamic>())
      .map((r) => MessageReaction(userId: r['userId'] as String, emoji: r['emoji'] as String))
      .toList();
}

MessageTick _confirmedTick({
  required String messageId,
  required List<Participant> otherParticipants,
  required bool isDirect,
}) {
  if (!isDirect || otherParticipants.isEmpty) return MessageTick.sent;
  final read = otherParticipants.any(
    (p) =>
        p.lastReadMessageId != null &&
        p.lastReadMessageId!.compareTo(messageId) >= 0,
  );
  if (read) return MessageTick.read;
  final delivered = otherParticipants.any(
    (p) =>
        p.lastDeliveredMessageId != null &&
        p.lastDeliveredMessageId!.compareTo(messageId) >= 0,
  );
  return delivered ? MessageTick.delivered : MessageTick.sent;
}
