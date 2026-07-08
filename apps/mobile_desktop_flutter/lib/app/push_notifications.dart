import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../firebase_options.dart';

/// FCM setup for Memory Circle.
///
/// This is intentionally tolerant: until Firebase project config is added with
/// `flutterfire configure`, initialization fails quietly and the app continues
/// with in-app queued notifications only.
class PushNotifications {
  PushNotifications(this.api);

  final ApiClient api;
  bool _initialized = false;
  StreamSubscription<String>? _refreshSubscription;

  Future<void> configureForSignedInUser() async {
    if (!await _ensureFirebase()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
      final token = vapidKey.isEmpty
          ? await messaging.getToken()
          : await messaging.getToken(vapidKey: vapidKey);
      if (token != null) {
        await api.registerNotificationSubscription(
          provider: 'fcm',
          endpoint: token,
          deviceLabel: kIsWeb ? 'Web browser' : defaultTargetPlatform.name,
        );
      }
      await _refreshSubscription?.cancel();
      _refreshSubscription = messaging.onTokenRefresh.listen((newToken) {
        api.registerNotificationSubscription(
          provider: 'fcm',
          endpoint: newToken,
          deviceLabel: kIsWeb ? 'Web browser' : defaultTargetPlatform.name,
        );
      });
    } catch (_) {
      // Push is best-effort; approval still works via in-app notifications.
    }
  }

  Future<bool> _ensureFirebase() async {
    if (_initialized) return true;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await _refreshSubscription?.cancel();
  }
}
