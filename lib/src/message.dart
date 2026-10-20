import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

/// A platform-independent view of a received push notification.
class PushMessage {
  /// Creates a message. Usually you get one from the plugin instead.
  const PushMessage({this.id, this.title, this.body, this.data = const {}});

  /// Builds a message from a Firebase [RemoteMessage].
  factory PushMessage.fromRemote(RemoteMessage message) => PushMessage(
        id: message.messageId,
        title: message.notification?.title,
        body: message.notification?.body,
        data: Map<String, dynamic>.from(message.data),
      );

  /// Restores a message from a local-notification payload created by
  /// [toPayload]. Returns an empty message if the payload is invalid.
  factory PushMessage.fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return const PushMessage();
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return PushMessage(
        id: map['id'] as String?,
        title: map['title'] as String?,
        body: map['body'] as String?,
        data: Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
      );
    } catch (_) {
      return const PushMessage();
    }
  }

  /// The FCM message id, if any.
  final String? id;

  /// Notification title.
  final String? title;

  /// Notification body.
  final String? body;

  /// The `data` map sent by your backend.
  final Map<String, dynamic> data;

  /// Convenience accessor for `data['route']`, the screen to open on tap.
  String? get route => data['route'] as String?;

  /// Serializes the message for a local-notification payload.
  String toPayload() =>
      jsonEncode({'id': id, 'title': title, 'body': body, 'data': data});

  @override
  String toString() => 'PushMessage(id: $id, title: $title, data: $data)';
}
