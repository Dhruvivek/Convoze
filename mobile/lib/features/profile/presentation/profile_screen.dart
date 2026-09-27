import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/realtime/connection_manager.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/loading_filled_button.dart';
import '../../auth/presentation/auth_state.dart';
import '../../conversations/data/media_repository.dart';
import '../data/profile_failure.dart';
import '../data/profile_repository.dart';

const _maxAboutLength = 140;
const _maxNameLength = 50;

/// The signed-in User's own profile (#43): name, about and avatar, all
/// editable, plus their (read-only) phone number. Reads its live values from
/// the local replica (seeded by [ProfileSync]/`refreshMe`) and writes
/// through [ProfileRepository].
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// True when shown as a bottom-nav tab body (no own app bar, and saving
  /// shows a confirmation instead of popping a route that isn't there).
  final bool embedded;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  bool _seeded = false;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _about = TextEditingController();
    // Best effort — a failed background refresh here just means the
    // screen shows whatever the replica already has (ADR 0009).
    Future.microtask(() => ref.read(profileRepositoryProvider).refreshMe().catchError((_) {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _save(String userId) async {
    setState(() => _saving = true);
    try {
      final trimmedName = _name.text.trim();
      final trimmedAbout = _about.text.trim();
      await ref
          .read(profileRepositoryProvider)
          .updateMe(
            displayName: trimmedName.isEmpty ? null : trimmedName,
            about: trimmedAbout.isEmpty ? null : trimmedAbout,
          );
      if (!mounted) return;
      if (widget.embedded) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      } else {
        context.pop();
      }
    } on ProfileFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .setAvatar(ref.read(mediaRepositoryProvider), File(picked.path));
    } on ProfileFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      await ref.read(profileRepositoryProvider).removeAvatar();
    } on ProfileFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String _message(ProfileFailure failure) => switch (failure) {
    ProfileNetworkFailure() => 'Needs a connection — try again once you\'re back online.',
    ProfileValidationFailure() => 'That name or about line isn\'t valid.',
    ProfileTooLarge() => 'That photo is too large.',
    ProfileRateLimited() => 'Too many changes — try again in a few minutes.',
    UnexpectedProfileFailure() => 'Something went wrong. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    if (auth is! Authenticated) return const SizedBox.shrink();
    final user = auth.user;
    final local = ref.watch(localUserProvider(user.id)).value;

    // Seeded once real replica data arrives, not on the first (possibly
    // still-loading) build — otherwise a slow-to-land row would seed from
    // the AuthState's stale sign-in-time snapshot and never get corrected.
    if (!_seeded && local != null) {
      _name.text = local.displayName ?? '';
      _about.text = local.about ?? '';
      _seeded = true;
    }

    final avatarUrl = local?.avatarUrl ?? user.avatarUrl;
    final online = ref.watch(connectionStatusProvider).value == ConnectionStatus.connected;
    final preview = _name.text.trim().isEmpty
        ? displayName(displayName: null, phoneNumber: user.phoneNumber)
        : _name.text.trim();

    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: online ? _changeAvatar : null,
                    child: AppAvatar(label: preview, seed: user.id, size: 96, avatarUrl: avatarUrl),
                  ),
                  if (_uploadingAvatar)
                    const SizedBox(
                      width: 96,
                      height: 96,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: online && !_uploadingAvatar ? _changeAvatar : null,
                    child: Text(avatarUrl == null ? 'Add photo' : 'Change photo'),
                  ),
                  if (avatarUrl != null)
                    TextButton(
                      onPressed: online && !_uploadingAvatar ? _removeAvatar : null,
                      child: const Text('Remove photo'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              enabled: online,
              maxLength: _maxNameLength,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            TextField(
              controller: _about,
              enabled: online,
              maxLength: _maxAboutLength,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'About'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(user.phoneNumber, style: Theme.of(context).textTheme.bodyMedium),
            if (!online) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Needs a connection to save changes.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            LoadingFilledButton(
              label: 'Save',
              loading: _saving,
              onPressed: online ? () => _save(user.id) : null,
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: content,
    );
  }
}
