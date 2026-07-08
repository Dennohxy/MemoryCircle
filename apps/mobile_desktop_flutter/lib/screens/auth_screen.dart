import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../i18n/index.dart';
import '../widgets/paper_card.dart';

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
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: LanguageSelector(),
                  ),
                  const SizedBox(height: Insets.md),
                  _brand(theme),
                  const SizedBox(height: Insets.xl),
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Insets.md),
                          Container(
                            padding:
                                const EdgeInsets.all(Insets.sm + Insets.xs),
                            decoration: BoxDecoration(
                              color: AppColors.rust.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
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
                            minimumSize: const Size.fromHeight(48),
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
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.softInk),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                  TextButton(
                    onPressed: _busy ? null : _fillDemoAccount,
                    child: Text(
                      context.t('auth.demoAccount'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.softInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.orange, AppColors.magenta],
            ),
          ),
          child: const Icon(
            Icons.auto_stories_outlined,
            size: 30,
            color: AppColors.ivory,
          ),
        ),
        const SizedBox(height: Insets.md),
        Text(context.t('common.displayName'),
            style: theme.textTheme.displaySmall),
        const SizedBox(height: Insets.sm),
        Text(
          context.t('common.tagline'),
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Insets.xs),
        Text(
          context.t('hero.meaning'),
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
