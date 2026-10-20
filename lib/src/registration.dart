import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Everything your backend needs to know about one device.
class DeviceRegistration {
  /// Creates a registration.
  const DeviceRegistration({
    required this.token,
    required this.platform,
    this.userId,
    this.appId,
    this.locale,
    this.properties = const {},
  });

  /// The FCM registration token of this device.
  final String token;

  /// Your own user id, set with `FcmIdentity.login`. `null` for anonymous
  /// devices.
  final String? userId;

  /// `android`, `ios`, `web`, `macos`, `windows` or `linux`.
  final String platform;

  /// Optional id of the app, useful when several apps share one Firebase
  /// project and one backend.
  final String? appId;

  /// The device locale as a BCP-47 tag, e.g. `tr-TR`.
  final String? locale;

  /// Custom key-value pairs (like OneSignal tags), set with
  /// `FcmIdentity.setProperties`.
  final Map<String, Object?> properties;

  /// The JSON body sent by [HttpRegistrar]. Null fields are omitted.
  Map<String, Object?> toJson() => {
        'token': token,
        if (userId != null) 'userId': userId,
        'platform': platform,
        if (appId != null) 'appId': appId,
        if (locale != null) 'locale': locale,
        if (properties.isNotEmpty) 'properties': properties,
      };
}

/// Sends device registrations to your backend.
///
/// Implement this to use your own HTTP client, GraphQL, Supabase, etc.
/// Throw from either method to signal a failure; the sync is retried
/// on the next app start or token change.
abstract interface class DeviceRegistrar {
  /// Creates or updates the device record. Backends should upsert by token.
  Future<void> register(DeviceRegistration registration);

  /// Removes the device record (called on logout).
  Future<void> unregister(DeviceRegistration registration);
}

/// Builds request headers, e.g. a fresh `Authorization` header.
typedef HeadersBuilder = FutureOr<Map<String, String>> Function();

/// Builds a custom JSON body if your backend expects a different shape.
typedef BodyBuilder = Map<String, Object?> Function(
  DeviceRegistration registration,
);

/// Thrown by [HttpRegistrar] when the backend answers with a non-2xx status.
class RegistrationException implements Exception {
  /// Creates the exception.
  const RegistrationException(this.statusCode, this.body);

  /// HTTP status code returned by the backend.
  final int statusCode;

  /// Response body returned by the backend.
  final String body;

  @override
  String toString() => 'RegistrationException($statusCode): $body';
}

/// A [DeviceRegistrar] that talks JSON over HTTP.
///
/// * register: `POST registerUrl` with the registration JSON.
/// * unregister: `POST unregisterUrl` if given, otherwise
///   `DELETE registerUrl`, with the same JSON body.
class HttpRegistrar implements DeviceRegistrar {
  /// Creates an HTTP registrar.
  HttpRegistrar({
    required this.registerUrl,
    this.unregisterUrl,
    this.headers,
    this.bodyBuilder,
    this.timeout = const Duration(seconds: 15),
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Endpoint that stores the device.
  final Uri registerUrl;

  /// Optional separate endpoint that removes the device.
  final Uri? unregisterUrl;

  /// Called before every request, so tokens can be refreshed.
  final HeadersBuilder? headers;

  /// Optional custom body; defaults to [DeviceRegistration.toJson].
  final BodyBuilder? bodyBuilder;

  /// Request timeout.
  final Duration timeout;

  final http.Client _client;

  @override
  Future<void> register(DeviceRegistration registration) =>
      _send('POST', registerUrl, registration);

  @override
  Future<void> unregister(DeviceRegistration registration) {
    final url = unregisterUrl;
    return url != null
        ? _send('POST', url, registration)
        : _send('DELETE', registerUrl, registration);
  }

  Future<void> _send(
    String method,
    Uri url,
    DeviceRegistration registration,
  ) async {
    final request = http.Request(method, url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...?await headers?.call(),
      })
      ..body = jsonEncode(
        bodyBuilder?.call(registration) ?? registration.toJson(),
      );

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RegistrationException(response.statusCode, response.body);
    }
  }
}

/// A [DeviceRegistrar] backed by two functions, for full control.
class CallbackRegistrar implements DeviceRegistrar {
  /// Creates a callback registrar.
  const CallbackRegistrar(
      {required this.onRegister, required this.onUnregister});

  /// Called to store the device.
  final Future<void> Function(DeviceRegistration registration) onRegister;

  /// Called to remove the device.
  final Future<void> Function(DeviceRegistration registration) onUnregister;

  @override
  Future<void> register(DeviceRegistration registration) =>
      onRegister(registration);

  @override
  Future<void> unregister(DeviceRegistration registration) =>
      onUnregister(registration);
}
