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

/// One row in a chat thread — either a confirmed [Message] or a still-queued
/// Outbox entry — with its [tick] already derived, so the screen never
/// compares watermarks itself.
class ChatMessageView {
  const ChatMessageView({
    required this.id,
    this.clientMsgId,
    required this.senderId,
    required this.fromMe,
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
  });

  /// The Message id, or the Outbox row's `clientMsgId` while still pending
  /// (ADR 0009: "which is also the id a pending Message row uses locally
  /// until the real one arrives").
  final String id;

  final String? clientMsgId;
  final String senderId;
  final bool fromMe;
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

  bool get isImage => type == 'image';
  bool get isFile => type == 'file';
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

  return [
    ...confirmed.map(
      (m) => ChatMessageView(
        id: m.id,
        clientMsgId: m.clientMsgId,
        senderId: m.senderId,
        fromMe: m.senderId == myUserId,
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
      ),
    ),
    ...pending.map((o) => _pendingView(o, myUserId)),
  ];
}

/// A pending Outbox row's view: its media fields (if any) come from the
/// JSON reference `MessagesRepository.sendMedia` queued (ADR 0009) — there's
/// no delivery URL yet, only what the upload itself reported, so
/// [ChatMessageView.mediaUrl]/[ChatMessageView.mediaThumbnailUrl] stay null
/// until the real Message lands.
ChatMessageView _pendingView(OutboxData o, String myUserId) {
  final media = o.media == null
      ? const <String, dynamic>{}
      : (jsonDecode(o.media!) as Map).cast<String, dynamic>();
  return ChatMessageView(
    id: o.clientMsgId,
    clientMsgId: o.clientMsgId,
    senderId: myUserId,
    fromMe: true,
    content: o.content,
    type: o.type,
    createdAt: o.createdAt,
    isDeleted: false,
    tick: o.status == 'failed' ? MessageTick.failed : MessageTick.clock,
    mediaWidth: media['width'] as int?,
    mediaHeight: media['height'] as int?,
    mediaFileName: media['fileName'] as String?,
    mediaBytes: media['bytes'] as int?,
  );
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
