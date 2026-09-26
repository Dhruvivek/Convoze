import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/loading_filled_button.dart';
import '../../auth/presentation/auth_state.dart';

/// Lets the signed-in User set the display name shown to others — there was
/// previously no screen anywhere that could do this. Saves locally via
/// [AuthState.updateDisplayName]; wiring a real profile-update backend call
/// later only changes that method's body.
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authStateProvider);
    _name = TextEditingController(text: auth is Authenticated ? (auth.user.displayName ?? '') : '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(authStateProvider.notifier).updateDisplayName(_name.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.embedded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    if (auth is! Authenticated) return const SizedBox.shrink();
    final user = auth.user;
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
              child: AppAvatar(label: preview, seed: user.id, size: 84),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(user.phoneNumber, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xl),
            LoadingFilledButton(label: 'Save', loading: _saving, onPressed: _save),
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
