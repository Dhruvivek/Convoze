import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../conversations/data/conversations_failure.dart';
import '../../conversations/data/conversations_repository.dart';
import '../../conversations/presentation/conversations_failure_message.dart';
import '../../conversations/presentation/media_viewer.dart';
import '../../presence/data/presence_providers.dart';
import '../../presence/presence_label.dart';
import '../data/profile_repository.dart';

/// Someone else's profile (#43): their photo (tap for full-screen), name,
/// about, phone number and presence, plus a Message button that opens (or
/// creates) a direct chat with them. Reached from a direct chat's header.
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    // ADR 0009: a profile only refreshes when something refers to it again
    // or a screen opens it — this is that second trigger.
    Future.microtask(
      () => ref.read(profileRepositoryProvider).refreshUser(widget.userId).catchError((_) {}),
    );
  }

  Future<void> _message() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversationId = await ref
          .read(conversationsRepositoryProvider)
          .openDirect(widget.userId);
      if (!mounted) return;
      context.push('/thread/$conversationId');
    } on ConversationsFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(conversationsFailureMessage(e))));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(localUserProvider(widget.userId)).value;
    final theme = Theme.of(context);

    final name = user == null
        ? ''
        : displayName(displayName: user.displayName, phoneNumber: user.phoneNumber);
    final presence = ref.watch(presenceProvider(widget.userId));
    final presenceText = presenceLabel(presence);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: user.avatarUrl == null
                          ? null
                          : () => showMediaViewer(context, url: user.avatarUrl!),
                      child: AppAvatar(label: name, seed: user.id, size: 120, avatarUrl: user.avatarUrl),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(child: Text(name, style: theme.textTheme.headlineSmall)),
                  if (presenceText.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Center(
                      child: Text(
                        presenceText,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                  if (user.about != null && user.about!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(user.about!, style: theme.textTheme.bodyLarge),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(user.phoneNumber, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    onPressed: _opening ? null : _message,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                  ),
                ],
              ),
            ),
    );
  }
}
