# Push Notifications

Omoide no Wa uses Firebase Cloud Messaging (FCM) for provider push delivery.
The app also stores in-app notification records, so approval workflows still
work when Firebase is not configured.

Current Firebase project:

```text
Display name: omoidenowa
Project ID:   omoienowa
Project no.:  65944243975
```

Google does not allow changing a project ID after creation; `omoienowa` remains
the stable project ID even though the display name is `omoidenowa`.

## Firebase Project

1. Open Firebase Console.
2. Create or select the Omoide no Wa project.
3. Add a Web app for the current Flutter web build.
4. Add Android/iOS apps later if native platform folders are generated.

## Flutter Setup

The Flutter packages are already added:

```text
firebase_core
firebase_messaging
```

Firebase client config has been generated from `apps/mobile_desktop_flutter`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=omoienowa --platforms=web
```

This created:

```text
lib/firebase_options.dart
```

For web push, the Firebase config has also been copied into:

```text
web/firebase-messaging-sw.js
```

Optional: set a public VAPID key at build time. If omitted, the app asks
Firebase Messaging for a token without a custom VAPID key.

```bash
flutter run -d chrome \
  --dart-define=API_BASE=http://127.0.0.1:8000 \
  --dart-define=FCM_WEB_VAPID_KEY=your_public_vapid_key
```

For deployment, pass the same `FCM_WEB_VAPID_KEY` define to `flutter build web`
only if you generated a custom Web Push certificate in Firebase Console.

## Backend Setup

The backend dependency is already added:

```text
firebase-admin
```

In Firebase Console:

1. Project Settings.
2. Service Accounts.
3. Generate new private key.

Local credentials were generated at:

```text
~/.config/memorycircle/firebase-service-account.json
```

Run the backend locally with:

```bash
export FIREBASE_CREDENTIALS="$HOME/.config/memorycircle/firebase-service-account.json"
python3 -m uvicorn app.main:app --reload
```

For deployment, configure one of these backend environment variables:

```bash
FIREBASE_CREDENTIALS=/secure/path/firebase-service-account.json
```

or:

```bash
FIREBASE_CREDENTIALS_JSON='{"type":"service_account",...}'
```

Do not commit service account JSON files.

## Runtime Flow

1. Signed-in Flutter app initializes Firebase if config exists.
2. App asks notification permission.
3. App sends the FCM device/browser token to:

```text
POST /me/notification-subscriptions
```

4. When photos need approval, the backend queues `photo_approval_needed`
   notifications and attempts FCM delivery to active subscriptions.
5. If Firebase is missing or delivery fails, notifications remain visible via:

```text
GET /me/notifications
```
