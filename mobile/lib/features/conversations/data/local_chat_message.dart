/// One row of a chat thread, joined live from the Local replica's `Messages`
/// table plus any not-yet-drained `Outbox` row for the same conversation
/// (ADR 0009: a sent message shows at once, before the server round-trip
/// confirms it). `id` is null for a still-pending Outbox-only row; `clientMsgId`
/// is the stable key either way, and is how a pending row and its landed
/// `Messages` row (once the sync engine drains it) are told apart from a
/// genuine duplicate.
class LocalChatMessage {
  const LocalChatMessage({
    this.clientMsgId,
    required this.senderIsMe,
    required this.content,
    required this.type,
    required this.isDeleted,
    required this.createdAt,
    required this.isPending,
    required this.isFailed,
    this.id,
    this.mediaPublicId,
    this.mediaResourceType,
    this.mediaBytes,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaFormat,
    this.mediaFileName,
    this.mediaUrl,
    this.mediaThumbnailUrl,
  });

  final String? id;

  /// Null for a Message from someone else (mirrors the `Messages` table's
  /// own column) — only this Device's own sends ever need to be matched
  /// against a pending Outbox row.
  final String? clientMsgId;
  final bool senderIsMe;
  final String? content;

  /// `'text'`, `'image'` or `'file'`.
  final String type;
  final bool isDeleted;
  final DateTime createdAt;

  /// Still sitting in the Outbox, not yet acknowledged by the server.
  final bool isPending;

  /// The Outbox drainer gave up on it (`status: 'failed'`) — "tap to retry
  /// or delete" is a later pass; for now this just renders differently.
  final bool isFailed;

  final String? mediaPublicId;
  final String? mediaResourceType;
  final int? mediaBytes;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? mediaFormat;
  final String? mediaFileName;
  final String? mediaUrl;
  final String? mediaThumbnailUrl;

  bool get isImage => type == 'image';
  bool get isFile => type == 'file';
}
