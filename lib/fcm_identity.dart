/// OneSignal-style push notifications on top of Firebase Cloud Messaging.
///
/// Call [FcmIdentity.init] once at startup, [FcmIdentity.login] when a user signs
/// in and [FcmIdentity.logout] when they sign out. Device tokens are synced to
/// your own backend through a [DeviceRegistrar].
library;

export 'src/config.dart';
export 'src/fcm_identity_base.dart';
export 'src/message.dart';
export 'src/registration.dart';
