import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/loading_filled_button.dart';
import '../../auth/presentation/auth_state.dart';
import '../../conversations/data/media_repository.dart';
import '../data/profile_failure.dart';
import '../data/profile_repository.dart';

/// The optional, skippable first-run step (#43): shown once right after a
/// Device's first sign-in, while the User has set neither a name nor a
/// photo. Only these two fields — about is left to My profile later, to
/// keep this a fast step rather than a full profile form.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  String? _avatarUrl;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(tokenStoreProvider).markProfileSetupSeen();
    if (!mounted) return;
    ref.read(authStateProvider.notifier).profileSetupSeen();
  }

  Future<void> _skip() => _finish();

  Future<void> _save() async {
    setState(() => _saving = true);
    final trimmed = _name.text.trim();
    try {
      if (trimmed.isNotEmpty) {
        await ref.read(profileRepositoryProvider).updateMe(displayName: trimmed, about: null);
      }
      await _finish();
    } on ProfileFailure catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't save right now — you can try again from My profile.")));
      await _finish();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .setAvatar(ref.read(mediaRepositoryProvider), File(picked.path));
      final auth = ref.read(authStateProvider);
      if (auth is Authenticated) {
        if (!mounted) return;
        setState(
          () => _avatarUrl = ref.read(localUserProvider(auth.user.id)).value?.avatarUrl,
        );
      }
    } on ProfileFailure catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't upload that photo.")));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final phoneNumber = auth is Authenticated ? auth.user.phoneNumber : '';
    final preview = _name.text.trim().isEmpty
        ? displayName(displayName: null, phoneNumber: phoneNumber)
        : _name.text.trim();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Set up your profile', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              const Text('Add a name and photo so people recognise you. You can skip this and do it later.'),
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: AppAvatar(label: preview, seed: phoneNumber, size: 96, avatarUrl: _avatarUrl),
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
                child: TextButton(
                  onPressed: _uploadingAvatar ? null : _pickAvatar,
                  child: Text(_avatarUrl == null ? 'Add photo' : 'Change photo'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _name,
                maxLength: 50,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: AppSpacing.lg),
              LoadingFilledButton(label: 'Save', loading: _saving, onPressed: _save),
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: _saving ? null : () => unawaited(_skip()), child: const Text('Skip')),
            ],
          ),
        ),
      ),
    );
  }
}
