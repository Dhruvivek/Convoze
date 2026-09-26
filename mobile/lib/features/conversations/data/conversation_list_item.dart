/// One row of the conversation list, joined live from the Local replica
/// (#51/#52) — the other participant's identity, a preview of the latest
/// Message, and this User's own Conversation preferences (#45), never
/// derived, only ever mirrored from the server (ADR 0009).
class ConversationListItem {
  const ConversationListItem({
    required this.id,
    required this.type,
    required this.otherUserId,
    required this.title,
    required this.avatarSeed,
    required this.previewText,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.left,
    required this.pinnedAt,
    required this.archivedAt,
    required this.mutedUntil,
    required this.hiddenAt,
  });

  final String id;

  /// `'direct'` or `'group'` — only `'direct'` conversations are listed
  /// today (ADR 0009: groups are #42's job).
  final String type;
  final String? otherUserId;
  final String title;
  final String avatarSeed;
  final String previewText;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool left;
  final DateTime? pinnedAt;
  final DateTime? archivedAt;
  final DateTime? mutedUntil;
  final DateTime? hiddenAt;

  bool get pinned => pinnedAt != null;
  bool get archived => archivedAt != null;

  /// A past `mutedUntil` just means "not muted any more" — there's no
  /// unmute job on either side (ADR 0009), this is computed live.
  bool get muted => mutedUntil != null && mutedUntil!.isAfter(DateTime.now());
}
