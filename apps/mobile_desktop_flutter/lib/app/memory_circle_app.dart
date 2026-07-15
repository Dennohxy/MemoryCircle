import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/index.dart';
import '../screens/auth_screen.dart';
import '../screens/circles_screen.dart';
import '../screens/guest_campaign_screen.dart';
import '../screens/reset_password_screen.dart';
import 'push_notifications.dart';
import 'theme.dart';

/// Root widget: owns the API client, restores the saved sign-in so family
/// members do not have to log in every time, and swaps between the auth
/// screen and the signed-in experience.
class MemoryCircleApp extends StatefulWidget {
  const MemoryCircleApp({super.key});

  @override
  State<MemoryCircleApp> createState() => _MemoryCircleAppState();
}

class _MemoryCircleAppState extends State<MemoryCircleApp> {
  final ApiClient _api = ApiClient();
  final I18nController _i18n = I18nController();
  late final PushNotifications _pushNotifications = PushNotifications(_api);
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  UserProfile? _user;
  bool _ready = false;

  /// A pending "join this circle" token read from the invite link URL
  /// (`?join=...`), applied once the person is signed in.
  String? _pendingJoinToken;

  /// A campaign token (`?campaign=...`): opens the no-login guest upload flow.
  String? _campaignToken;

  /// A password-reset token (`?reset=...`): opens the reset screen.
  String? _resetToken;

  /// Bumped after joining a circle so the circle list reloads.
  int _circlesReloadKey = 0;

  @override
  void initState() {
    super.initState();
    _api.onSessionExpired = _sessionExpired;
    final params = Uri.base.queryParameters;
    final token = params['join'];
    if (token != null && token.isNotEmpty) _pendingJoinToken = token;
    final campaign = params['campaign'];
    if (campaign != null && campaign.isNotEmpty) _campaignToken = campaign;
    final reset = params['reset'];
    if (reset != null && reset.isNotEmpty) _resetToken = reset;
    unawaited(_i18n.load());
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = await _api.restoreSession();
    if (mounted) {
      setState(() {
        _user = user;
        _ready = true;
      });
    }
    if (user != null) {
      unawaited(_pushNotifications.configureForSignedInUser());
    }
    await _maybeAcceptPendingJoin();
  }

  void _onSignedIn(UserProfile user) {
    setState(() => _user = user);
    unawaited(_pushNotifications.configureForSignedInUser());
    _maybeAcceptPendingJoin();
  }

  /// If the app was opened from an invite link, join that circle now.
  Future<void> _maybeAcceptPendingJoin() async {
    final token = _pendingJoinToken;
    if (token == null || _user == null) return;
    _pendingJoinToken = null;
    try {
      final circle = await _api.acceptInviteLink(token);
      if (!mounted) return;
      setState(() => _circlesReloadKey++);
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content:
            Text(_i18n.t('circles.joined', values: {'circle': circle.name})),
      ));
    } on ApiException {
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(_i18n.t('circles.inviteInactive')),
      ));
    }
  }

  /// The saved sign-in stopped working (for example after 30 days); return
  /// to the sign-in screen without stranding the user on a broken page.
  void _sessionExpired() {
    if (!mounted || _user == null) return;
    _api.signOut();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _user = null);
    _messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(_i18n.t('circles.sessionExpired')),
    ));
  }

  void _signOut() {
    _api.signOut();
    setState(() => _user = null);
  }

  @override
  void dispose() {
    _pushNotifications.dispose();
    _i18n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return I18nScope(
      controller: _i18n,
      child: Builder(
        builder: (context) => MaterialApp(
          title: context.t('metadata.title'),
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          home: !_ready
              ? const _SplashScreen()
              // A campaign link opens the guest flow for anyone, logged in or
              // not — it never requires an account.
              : _campaignToken != null
                  ? GuestCampaignScreen(api: _api, token: _campaignToken!)
                  : (_resetToken != null && _user == null)
                      ? ResetPasswordScreen(
                          api: _api,
                          token: _resetToken!,
                          onDone: (user) => setState(() {
                            _resetToken = null;
                            _user = user;
                          }),
                        )
                      : _user == null
                          ? AuthScreen(
                              api: _api,
                              onSignedIn: _onSignedIn,
                            )
                          : CirclesScreen(
                              key: ValueKey(_circlesReloadKey),
                              api: _api,
                              user: _user!,
                              onSignOut: _signOut,
                            ),
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: Insets.lg),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
