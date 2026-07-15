import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../i18n/index.dart';

/// Sign in / create account screen.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.onSignedIn});

  final ApiClient api;
  final void Function(UserProfile user) onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillLastEmail();
  }

  /// Prefills the email used last time on this device.
  Future<void> _prefillLastEmail() async {
    final email = await widget.api.lastEmail();
    if (mounted && email != null && _emailController.text.isEmpty) {
      _emailController.text = email;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    String? problem;
    if (_registerMode && name.isEmpty) {
      problem = context.t('auth.nameProblem');
    } else if (email.isEmpty || !email.contains('@')) {
      problem = context.t('auth.emailProblem');
    } else if (password.isEmpty) {
      problem = context.t('auth.passwordProblem');
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _registerMode
          ? await widget.api
              .register(displayName: name, email: email, password: password)
          : await widget.api.login(email: email, password: password);
      if (mounted) widget.onSignedIn(user);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = switch (error.statusCode) {
            401 => context.t('auth.badCredentials'),
            409 => context.t('auth.emailExists'),
            _ => error.message,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemoAccount() {
    setState(() {
      _registerMode = false;
      _emailController.text = 'owner@example.com';
      _passwordController.text = 'Password123!';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF081126), Color(0xFF101B3D)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 56 : Insets.lg,
                  vertical: Insets.lg,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - Insets.lg * 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerRight,
                        child: _LandingLanguageSelector(),
                      ),
                      const SizedBox(height: Insets.lg),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              flex: 6,
                              child: _LandingIntro(),
                            ),
                            const SizedBox(width: 56),
                            Expanded(flex: 4, child: _authPanel(context)),
                          ],
                        )
                      else ...[
                        const _LandingIntro(compact: true),
                        const SizedBox(height: Insets.xl),
                        _authPanel(context),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _authPanel(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.t('auth.panelTitle'),
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: Insets.xs),
            Text(
              context.t('common.tagline'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.softInk),
            ),
            const SizedBox(height: Insets.lg),
            Center(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(context.t('common.signIn')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(context.t('common.createAccount')),
                  ),
                ],
                selected: {_registerMode},
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() {
                          _registerMode = selection.first;
                          _error = null;
                        }),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: Insets.lg),
            if (_registerMode) ...[
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: appInput(
                  context.t('common.yourName'),
                  hint: context.t('auth.nameHint'),
                ),
              ),
              const SizedBox(height: Insets.md),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: appInput(context.t('common.email')),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: appInput(
                context.t('common.password'),
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? context.t('auth.showPassword')
                      : context.t('auth.hidePassword'),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (!_registerMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (_) => _ForgotPasswordDialog(
                              api: widget.api,
                              initialEmail: _emailController.text.trim(),
                            ),
                          ),
                  child: const Text('Forgot password?'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Container(
                padding: const EdgeInsets.all(Insets.sm + Insets.xs),
                decoration: BoxDecoration(
                  color: AppColors.rust.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 20, color: AppColors.rust),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.rust),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Insets.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _registerMode
                          ? context.t('common.createAccount')
                          : context.t('common.signIn'),
                    ),
            ),
            const SizedBox(height: Insets.sm),
            Text(
              _registerMode
                  ? context.t('auth.createAccountHelp')
                  : context.t('auth.signInHelp'),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.sm),
            TextButton(
              onPressed: _busy ? null : _fillDemoAccount,
              child: Text(context.t('auth.demoAccount')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingIntro extends StatelessWidget {
  const _LandingIntro({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        (compact ? theme.textTheme.displaySmall : theme.textTheme.displayMedium)
            ?.copyWith(color: Colors.white, height: 1.05);
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Image.asset(
          'web/logo-mark-transparent.png',
          width: compact ? 104 : 132,
          height: compact ? 104 : 132,
        ),
        const SizedBox(height: Insets.lg),
        Text(
          context.t('common.displayName'),
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            letterSpacing: 0.3,
          ),
          textAlign: compact ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: Insets.sm),
        Text(
          context.t('hero.title'),
          style: titleStyle,
          textAlign: compact ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: Insets.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            context.t('hero.subtitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
            textAlign: compact ? TextAlign.center : TextAlign.start,
          ),
        ),
        const SizedBox(height: Insets.xl),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            _LandingCue(
              icon: Icons.lock_outline,
              label: context.t('hero.privacyCue'),
            ),
            _LandingCue(
              icon: Icons.how_to_vote_outlined,
              label: context.t('hero.approvalCue'),
            ),
            _LandingCue(
              icon: Icons.auto_stories_outlined,
              label: context.t('hero.albumCue'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LandingCue extends StatelessWidget {
  const _LandingCue({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.sun),
            const SizedBox(width: Insets.sm),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingLanguageSelector extends StatelessWidget {
  const _LandingLanguageSelector();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: Insets.sm),
        child: LanguageSelector(),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.api, this.initialEmail = ''});

  final ApiClient api;
  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final _emailController =
      TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _sent = false;
  bool _emailEnabled = true;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) return;
    setState(() => _busy = true);
    try {
      final enabled = await widget.api.forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _emailEnabled = enabled;
      });
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_sent) {
      return AlertDialog(
        title: const Text('Check your email'),
        content: Text(
          _emailEnabled
              ? 'If an account exists for that email, we\'ve sent a link to '
                  'reset your password. It expires in 1 hour.'
              : 'Password reset by email isn\'t set up yet. Please contact the '
                  'person who runs this circle.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Reset your password'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your email and we\'ll send you a link to set a new password.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.softInk),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: appInput('Email'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Sending…' : 'Send link'),
        ),
      ],
    );
  }
}
