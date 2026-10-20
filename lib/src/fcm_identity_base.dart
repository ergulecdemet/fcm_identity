import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'message.dart';
import 'registration.dart';

/// Default handler for messages received while the app is terminated or in
/// the background. Messages with a `notification` block are displayed by the
/// OS; this only makes sure Firebase is initialized in the background isolate.
@pragma('vm:entry-point')
Future<void> _defaultBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

/// OneSignal-style facade over Firebase Cloud Messaging.
///
/// ```dart
/// await FcmIdentity.instance.init(FcmIdentityConfig(
///   firebaseOptions: DefaultFirebaseOptions.currentPlatform,
///   registrar: HttpRegistrar(
///     registerUrl: Uri.parse('https://api.example.com/devices'),
///   ),
/// ));
///
/// await FcmIdentity.instance.login('12345');
/// await FcmIdentity.instance.logout();
/// ```
class FcmIdentity {
  FcmIdentity._();

  /// The single instance.
  static final FcmIdentity instance = FcmIdentity._();

  static const _kUserId = 'fcm_identity.user_id';
  static const _kProperties = 'fcm_identity.properties';
  static const _kSynced = 'fcm_identity.synced';

  FcmIdentityConfig? _config;
  FcmIdentityConfig get _cfg =>
      _config ?? (throw StateError('Call FcmIdentity.instance.init() first.'));

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  final List<StreamSubscription<dynamic>> _subs = [];
  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _opened =
      StreamController<PushMessage>.broadcast();

  String? _token;
  String? _userId;
  Map<String, Object?> _properties = {};
  PushMessage? _initialMessage;
  Future<void> _queue = Future<void>.value();

  /// Whether [init] has completed.
  bool get isInitialized => _config != null;

  /// The current FCM token, once available.
  String? get token => _token;

  /// The logged-in user id, persisted across app restarts.
  String? get userId => _userId;

  /// Properties currently attached to this device.
  Map<String, Object?> get properties => Map.unmodifiable(_properties);

  /// Messages received while the app is in the foreground.
  Stream<PushMessage> get onMessage => _messages.stream;

  /// Notifications tapped while the app is running or in the background.
  Stream<PushMessage> get onMessageOpened => _opened.stream;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  /// Initializes Firebase and the plugin. Call once, before `runApp`.
  ///
  /// Returns quickly: fetching the token and syncing with your backend
  /// happen in the background.
  Future<void> init(FcmIdentityConfig config) async {
    if (_config != null) return;
    _config = config;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: config.firebaseOptions);
    }

    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString(_kUserId);
    _properties = _decodeMap(prefs.getString(_kProperties));

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        config.backgroundHandler ?? _defaultBackgroundHandler,
      );
      await _initLocalNotifications();
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: config.showForegroundNotifications,
      badge: true,
      sound: config.showForegroundNotifications,
    );

    _subs
      ..add(FirebaseMessaging.onMessage.listen(_handleForeground))
      ..add(FirebaseMessaging.onMessageOpenedApp
          .listen((m) => _emitOpened(PushMessage.fromRemote(m))))
      // Token APIs are deprecated in favor of Firebase Installation ID based
      // registration. They still work; migration is planned for a later version.
      // ignore: deprecated_member_use
      ..add(_messaging.onTokenRefresh.listen((t) {
        _token = t;
        _scheduleSync();
      }));

    await _captureInitialMessage();

    if (config.requestPermissionOnInit) {
      unawaited(requestPermission());
    } else {
      unawaited(_refreshToken());
    }
  }

  Future<void> _initLocalNotifications() async {
    await _local.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(_cfg.androidIcon),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _emitOpened(PushMessage.fromPayload(response.payload)),
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            _cfg.androidChannelId,
            _cfg.androidChannelName,
            description: _cfg.androidChannelDescription,
            importance: Importance.high,
          ),
        );
  }

  Future<void> _captureInitialMessage() async {
    final remote = await _messaging.getInitialMessage();
    if (remote != null) {
      _initialMessage = PushMessage.fromRemote(remote);
      return;
    }
    if (kIsWeb) return;
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _initialMessage =
          PushMessage.fromPayload(launch!.notificationResponse?.payload);
    }
  }

  // ---------------------------------------------------------------------------
  // Permission
  // ---------------------------------------------------------------------------

  /// Shows the system permission prompt (Android 13+, iOS, web).
  /// Returns `true` if notifications are allowed.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted = _isGranted(settings.authorizationStatus);
    if (granted) await _refreshToken();
    return granted;
  }

  /// Whether notifications are currently allowed.
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return _isGranted(settings.authorizationStatus);
  }

  bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  // ---------------------------------------------------------------------------
  // Users (OneSignal-style)
  // ---------------------------------------------------------------------------

  /// Links this device to [userId] and registers it with your backend.
  /// The id is persisted, so you only need to call this after sign-in.
  ///
  /// Optional [properties] are merged into the device properties.
  Future<void> login(String userId, {Map<String, Object?>? properties}) async {
    _ensureInitialized();
    _userId = userId;
    if (properties != null) _properties = {..._properties, ...properties};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, userId);
    await prefs.setString(_kProperties, jsonEncode(_properties));
    if (_token == null) {
      await _refreshToken();
    } else {
      await _scheduleSync();
    }
  }

  /// Unregisters this device from your backend and forgets the user.
  /// With [FcmIdentityConfig.deleteTokenOnLogout] the FCM token is deleted too.
  Future<void> logout() async {
    final cfg = _cfg;
    await _queue;

    final token = _token;
    if (token != null && _userId != null) {
      try {
        await cfg.registrar.unregister(_registration(token));
      } catch (e, st) {
        _reportError(e, st);
      }
    }

    _userId = null;
    _properties = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kProperties);
    await prefs.remove(_kSynced);

    if (cfg.deleteTokenOnLogout && token != null) {
      try {
        // ignore: deprecated_member_use
        await _messaging.deleteToken();
      } catch (e, st) {
        _reportError(e, st);
      }
      _token = null;
      if (cfg.registerAnonymousDevices) await _refreshToken();
    } else if (cfg.registerAnonymousDevices) {
      await _scheduleSync();
    }
  }

  /// Merges [properties] into the device properties (like OneSignal tags)
  /// and syncs them. Set a value to `null` to remove it.
  Future<void> setProperties(Map<String, Object?> properties) async {
    _ensureInitialized();
    final merged = {..._properties, ...properties}
      ..removeWhere((_, v) => v == null);
    _properties = merged;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProperties, jsonEncode(_properties));
    await _scheduleSync();
  }

  /// Sets a single property. See [setProperties].
  Future<void> setProperty(String key, Object? value) =>
      setProperties({key: value});

  // ---------------------------------------------------------------------------
  // Token & sync
  // ---------------------------------------------------------------------------

  Future<void> _refreshToken() async {
    _token = await _fetchToken();
    await _scheduleSync();
  }

  Future<String?> _fetchToken() async {
    try {
      if (_isApple) {
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns == null) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        if (apns == null) {
          debugPrint('[fcm_identity] No APNs token. Check the Push '
              'Notifications capability and use a real device.');
          return null;
        }
      }
      // ignore: deprecated_member_use
      return await _messaging.getToken(
        vapidKey: kIsWeb ? _cfg.webVapidKey : null,
      );
    } catch (e, st) {
      _reportError(e, st);
      return null;
    }
  }

  /// Runs syncs one after another, never in parallel.
  Future<void> _scheduleSync() {
    _queue = _queue.then((_) => _sync());
    return _queue;
  }

  Future<void> _sync() async {
    final cfg = _cfg;
    final token = _token;
    if (token == null) return;
    if (_userId == null && !cfg.registerAnonymousDevices) return;

    final registration = _registration(token);
    final fingerprint = jsonEncode(registration.toJson());
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kSynced) == fingerprint) return;

    try {
      await cfg.registrar.register(registration);
      await prefs.setString(_kSynced, fingerprint);
    } catch (e, st) {
      // Not saved as synced, so it is retried on the next start or change.
      _reportError(e, st);
    }
  }

  DeviceRegistration _registration(String token) => DeviceRegistration(
        token: token,
        userId: _userId,
        platform: _platformName(),
        appId: _cfg.appId,
        locale: PlatformDispatcher.instance.locale.toLanguageTag(),
        properties: _properties,
      );

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  // ---------------------------------------------------------------------------
  // Topics (optional)
  // ---------------------------------------------------------------------------

  /// Subscribes to a topic (prefixed with [FcmIdentityConfig.topicPrefix]).
  /// Not supported on web; subscribe from your backend there.
  Future<void> subscribe(String topic) async {
    if (kIsWeb) return;
    await _messaging.subscribeToTopic('${_cfg.topicPrefix}$topic');
  }

  /// Unsubscribes from a topic.
  Future<void> unsubscribe(String topic) async {
    if (kIsWeb) return;
    await _messaging.unsubscribeFromTopic('${_cfg.topicPrefix}$topic');
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Returns the notification that launched the app from a terminated
  /// state, once. Call it after your router is ready.
  PushMessage? takeInitialMessage() {
    final message = _initialMessage;
    _initialMessage = null;
    return message;
  }

  void _handleForeground(RemoteMessage remote) {
    final message = PushMessage.fromRemote(remote);
    _cfg.onMessage?.call(message);
    _messages.add(message);

    // Apple platforms display it via presentation options; Android does not.
    if (_isAndroid &&
        _cfg.showForegroundNotifications &&
        remote.notification != null) {
      unawaited(_showLocal(message));
    }
  }

  Future<void> _showLocal(PushMessage message) async {
    final id =
        (message.id ?? DateTime.now().toIso8601String()).hashCode & 0x7fffffff;
    await _local.show(
      id: id,
      title: message.title,
      body: message.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _cfg.androidChannelId,
          _cfg.androidChannelName,
          channelDescription: _cfg.androidChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _cfg.androidIcon,
        ),
      ),
      payload: message.toPayload(),
    );
  }

  void _emitOpened(PushMessage message) {
    _cfg.onMessageOpened?.call(message);
    _opened.add(message);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _ensureInitialized() {
    if (_config == null) {
      throw StateError('Call FcmIdentity.instance.init() first.');
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    debugPrint('[fcm_identity] $error');
    _config?.onError?.call(error, stackTrace);
  }

  static Map<String, Object?> _decodeMap(String? raw) {
    if (raw == null) return {};
    try {
      return Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Cancels listeners. Mainly for tests.
  @visibleForTesting
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _config = null;
  }
}
