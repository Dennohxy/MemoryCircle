import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../screens/auth_screen.dart';
import '../screens/circles_screen.dart';
import 'theme.dart';

/// Root widget: owns the API client and swaps between the auth screen and
/// the signed-in experience.
class MemoryCircleApp extends StatefulWidget {
  const MemoryCircleApp({super.key});

  @override
  State<MemoryCircleApp> createState() => _MemoryCircleAppState();
}

class _MemoryCircleAppState extends State<MemoryCircleApp> {
  final ApiClient _api = ApiClient();
  UserProfile? _user;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memory Circle',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _user == null
          ? AuthScreen(
              api: _api,
              onSignedIn: (user) => setState(() => _user = user),
            )
          : CirclesScreen(
              api: _api,
              user: _user!,
              onSignOut: () {
                _api.signOut();
                setState(() => _user = null);
              },
            ),
    );
  }
}
