import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../screens/auth_screen.dart';
import '../screens/circles_screen.dart';
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
  late final PushNotifications _pushNotifications = PushNotifications(_api);
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  UserProfile? _user;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _api.onSessionExpired = _sessionExpired;
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
  }

  /// The saved sign-in stopped working (for example after 30 days); return
  /// to the sign-in screen without stranding the user on a broken page.
  void _sessionExpired() {
    if (!mounted || _user == null) return;
    _api.signOut();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _user = null);
    _messengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('Welcome back! Please sign in again to continue.'),
    ));
  }

  void _signOut() {
    _api.signOut();
    setState(() => _user = null);
  }

  @override
  void dispose() {
    _pushNotifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memory Circle',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      home: !_ready
          ? const _SplashScreen()
          : _user == null
              ? AuthScreen(
                  api: _api,
                  onSignedIn: (user) {
                    setState(() => _user = user);
                    unawaited(_pushNotifications.configureForSignedInUser());
                  },
                )
              : CirclesScreen(
                  api: _api,
                  user: _user!,
                  onSignOut: _signOut,
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
                  colors: [AppColors.deepGreen, AppColors.forest],
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
