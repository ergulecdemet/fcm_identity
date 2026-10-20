import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'message.dart';
import 'registration.dart';

/// Configuration passed to `FcmIdentity.init`.
class FcmIdentityConfig {
  /// Creates a configuration. Only [registrar] is required.
  const FcmIdentityConfig({
    required this.registrar,
    this.firebaseOptions,
    this.appId,
    this.registerAnonymousDevices = false,
    this.deleteTokenOnLogout = true,
    this.requestPermissionOnInit = false,
    this.showForegroundNotifications = true,
    this.topicPrefix = '',
    this.androidChannelId = 'fcm_identity_default',
    this.androidChannelName = 'Notifications',
    this.androidChannelDescription = 'General notifications',
    this.androidIcon = '@mipmap/ic_launcher',
    this.webVapidKey,
    this.backgroundHandler,
    this.onMessage,
    this.onMessageOpened,
    this.onError,
  });

  /// Where device registrations are sent: your backend.
  final DeviceRegistrar registrar;

  /// Usually `DefaultFirebaseOptions.currentPlatform` from `flutterfire
  /// configure`. If null, the native config files are used.
  final FirebaseOptions? firebaseOptions;

  /// Optional app identifier included in every registration.
  final String? appId;

  /// Register devices with your backend even before `login` is called
  /// (with `userId: null`). Useful for broadcast-only apps.
  final bool registerAnonymousDevices;

  /// Delete the FCM token on logout so the device stops receiving
  /// notifications that were addressed to the previous user.
  final bool deleteTokenOnLogout;

  /// Ask for notification permission during `init`. Prefer `false` and
  /// call `FcmIdentity.requestPermission` after explaining why.
  final bool requestPermissionOnInit;

  /// Show notifications while the app is in the foreground.
  final bool showForegroundNotifications;

  /// Prefix added to every topic name; avoids clashes when several apps
  /// share one Firebase project.
  final String topicPrefix;

  /// Android notification channel id. Also set it in AndroidManifest as
  /// `com.google.firebase.messaging.default_notification_channel_id`.
  final String androidChannelId;

  /// Android notification channel name shown in system settings.
  final String androidChannelName;

  /// Android notification channel description.
  final String androidChannelDescription;

  /// Android small icon resource.
  final String androidIcon;

  /// VAPID key, required on web only.
  final String? webVapidKey;

  /// Your own background handler. Must be a top-level function annotated
  /// with `@pragma('vm:entry-point')`.
  final BackgroundMessageHandler? backgroundHandler;

  /// Called when a message arrives while the app is in the foreground.
  final void Function(PushMessage message)? onMessage;

  /// Called when the user taps a notification while the app is running
  /// or in the background. For cold starts use `takeInitialMessage`.
  final void Function(PushMessage message)? onMessageOpened;

  /// Called when syncing with the backend or Firebase fails.
  final void Function(Object error, StackTrace stackTrace)? onError;
}
