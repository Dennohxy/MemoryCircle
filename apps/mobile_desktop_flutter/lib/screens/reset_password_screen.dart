import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';

/// Shown when the app is opened from a password-reset link (`?reset=TOKEN`).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.api,
    required this.token,
    required this.onDone,
  });

  final ApiClient api;
  final String token;
  final ValueChanged<UserProfile> onDone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.length < 8) {
      setState(() => _error = 'Choose a password with at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.api
          .resetPassword(token: widget.token, newPassword: password);
      widget.onDone(user);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Choose a new password',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: Insets.sm),
                Text(
                  'Enter a new password for your Omoide no Wa account.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.softInk),
                ),
                const SizedBox(height: Insets.lg),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                  decoration: appInput('New password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Insets.sm),
                  Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.attention)),
                ],
                const SizedBox(height: Insets.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Set new password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
