# fcm_identity

**English** | [Türkçe](README.tr.md)

OneSignal-style push notifications on top of **Firebase Cloud Messaging**, with **your own backend** in control.

```dart
await FcmIdentity.instance.init(FcmIdentityConfig(
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  registrar: HttpRegistrar(
    registerUrl: Uri.parse('https://api.example.com/devices'),
  ),
));

await FcmIdentity.instance.login('12345');   // after sign-in
await FcmIdentity.instance.logout();         // after sign-out
```

Firebase only knows devices, not users. `fcm_identity` keeps the *user ↔ device* mapping in sync with your backend, the way `OneSignal.login()` did:

* gets and refreshes the FCM token (waits for APNs on iOS),
* sends `{ token, userId, platform, locale, properties }` to your API on login, token refresh and property changes, and only when something changed,
* retries failed syncs on the next app start,
* unregisters and deletes the token on logout,
* shows notifications in the foreground on Android,
* reports taps, including the one that cold-started the app.

The package never holds secrets. Your backend sends notifications with its own Firebase service account.

| OneSignal | fcm_identity |
|---|---|
| `OneSignal.initialize(appId)` | `FcmIdentity.instance.init(config)` |
| `OneSignal.login(externalId)` | `FcmIdentity.instance.login(userId)` |
| `OneSignal.logout()` | `FcmIdentity.instance.logout()` |
| `OneSignal.User.addTags({...})` | `FcmIdentity.instance.setProperties({...})` |
| `OneSignal.Notifications.requestPermission()` | `FcmIdentity.instance.requestPermission()` |
| REST API key on your server | Firebase service account JSON on your server |

## Installation

```bash
flutter pub add fcm_identity
dart pub global activate flutterfire_cli
flutterfire configure
```

### Android

Core library desugaring is required by `flutter_local_notifications`.

`android/app/build.gradle.kts` (Kotlin DSL, default for new Flutter projects):

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

`android/app/build.gradle` (Groovy, older projects):

```gradle
android {
    compileOptions {
        coreLibraryDesugaringEnabled true
    }
}
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

`AndroidManifest.xml`, inside `<application>`:

```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="fcm_identity_default" />
```

The value must match `FcmIdentityConfig.androidChannelId`.

### iOS

1. In Xcode, add **Push Notifications** and **Background Modes → Remote notifications**.
2. Upload an APNs auth key (.p8) in Firebase Console → Project settings → Cloud Messaging.
3. Test on a real device.

## Usage

### Initialize

```dart
await FcmIdentity.instance.init(FcmIdentityConfig(
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  registrar: HttpRegistrar(
    registerUrl: Uri.parse('https://api.example.com/devices'),
    // Called before every request, so expired tokens are never sent.
    headers: () async => {'Authorization': 'Bearer ${await auth.idToken()}'},
  ),
  onMessageOpened: (m) => router.push(m.route ?? '/'),
));
```

`init` returns quickly. The token is fetched and synced in the background.

### Permission

```dart
final granted = await FcmIdentity.instance.requestPermission();
```

Ask after explaining why, not on first launch. Set `requestPermissionOnInit: true` to ask during `init` instead.

### Users and properties

```dart
await FcmIdentity.instance.login('12345', properties: {'plan': 'pro'});
await FcmIdentity.instance.setProperty('city', 'gaziantep');
await FcmIdentity.instance.setProperty('city', null); // remove
await FcmIdentity.instance.logout();
```

The user id and properties are persisted. You don't need to call `login` on every start.

Avoid putting personal data (names, emails, phone numbers) in properties. Your backend already knows the user by `userId`, and properties are stored unencrypted on the device.

### Opening screens from notifications

Send `data: { route: '/orders/7' }` from your backend.

```dart
// Running or in background
FcmIdentity.instance.onMessageOpened.listen((m) => router.push(m.route!));

// Cold start: call once your router is ready
final initial = FcmIdentity.instance.takeInitialMessage();
if (initial?.route != null) router.go(initial!.route!);
```

### Foreground messages

```dart
FcmIdentity.instance.onMessage.listen((m) => showSnackBar(m.title));
```

### Topics (optional)

```dart
await FcmIdentity.instance.subscribe('news'); // "<topicPrefix>news"
```

Use `topicPrefix` when several apps share one Firebase project.

### Custom backend shape

```dart
HttpRegistrar(
  registerUrl: Uri.parse('https://api.example.com/push-token'),
  unregisterUrl: Uri.parse('https://api.example.com/push-token/remove'),
  bodyBuilder: (r) => {'pushToken': r.token, 'device': r.platform},
)
```

Or use any client you like:

```dart
CallbackRegistrar(
  onRegister: (r) async {
    await supabase.from('devices').upsert(r.toJson());
  },
  onUnregister: (r) async {
    await supabase.from('devices').delete().eq('token', r.token);
  },
)
```

## Backend contract

With the default `HttpRegistrar`:

| Event | Request | Body |
|---|---|---|
| login, token refresh, property change | `POST registerUrl` | `{ token, userId, platform, appId?, locale?, properties? }` |
| logout | `DELETE registerUrl` (or `POST unregisterUrl`) | same |

Any non-2xx response is treated as a failure and retried on the next app start.

Your backend should **upsert by `token`**. A token belongs to one device; if it shows up with a new `userId`, move it. Always take the user id from the authenticated session, not from the request body alone.

See [doc/backend.md](doc/backend.md) for a complete Node.js example, including sending to a user and cleaning up dead tokens.

## License

MIT
