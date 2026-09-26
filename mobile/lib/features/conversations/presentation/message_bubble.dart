import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/local_chat_message.dart';
import 'media_viewer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onLongPress});

  final LocalChatMessage message;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.senderIsMe;
    final deleted = message.isDeleted;
    final background = deleted
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : mine
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final foreground = deleted
        ? scheme.onSurfaceVariant
        : mine
        ? scheme.onPrimary
        : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        // A still-uploading/queued message shows dimmed rather than with a
        // full progress affordance — this reduced-scope pass doesn't build
        // per-row upload progress, only "on its way" vs "sent" (ADR 0009's
        // "it appears at once" without the full resilience UI of #40/#54).
        opacity: message.isPending ? 0.6 : 1,
        child: GestureDetector(
          onLongPress: deleted ? null : onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
            padding: message.isImage
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (deleted)
                  Text(
                    'This message was deleted',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15.5,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (message.isImage)
                  _ImageContent(message: message, foreground: foreground)
                else if (message.isFile)
                  _FileContent(message: message, foreground: foreground)
                else ...[
                  Text(
                    message.content ?? '',
                    style: TextStyle(color: foreground, fontSize: 15.5, height: 1.3),
                  ),
                  if (message.editedAt != null)
                    Text(
                      '(edited)',
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.65),
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
                if (!deleted && mine) ...[
                  const SizedBox(height: 2),
                  Icon(
                    message.isFailed
                        ? Icons.error_outline
                        : message.isPending
                        ? Icons.schedule
                        : Icons.check,
                    size: 14,
                    color: foreground.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.message, required this.foreground});

  final LocalChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final url = message.mediaThumbnailUrl ?? message.mediaUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: message.mediaUrl == null
                ? null
                : () => showMediaViewer(context, url: message.mediaUrl!),
            child: AspectRatio(
              aspectRatio: (message.mediaWidth != null && message.mediaHeight != null)
                  ? message.mediaWidth! / message.mediaHeight!
                  : 1,
              child: url == null
                  ? Container(color: Colors.black12, child: const Icon(Icons.image_outlined))
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
        ),
        if ((message.content ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, 0),
            child: Text(message.content!, style: TextStyle(color: foreground, fontSize: 15)),
          ),
      ],
    );
  }
}

class _FileContent extends StatelessWidget {
  const _FileContent({required this.message, required this.foreground});

  final LocalChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, color: foreground),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.mediaFileName ?? 'Document',
                style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              if (message.mediaBytes != null)
                Text(
                  _humanSize(message.mediaBytes!),
                  style: TextStyle(color: foreground.withValues(alpha: 0.7), fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
