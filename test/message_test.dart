import 'package:fcm_identity/src/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payload round-trip keeps all fields', () {
    const original = PushMessage(
      id: '1',
      title: 'Hello',
      body: 'World',
      data: {'route': '/orders/7'},
    );
    final restored = PushMessage.fromPayload(original.toPayload());
    expect(restored.id, '1');
    expect(restored.title, 'Hello');
    expect(restored.body, 'World');
    expect(restored.route, '/orders/7');
  });

  test('invalid payload gives an empty message', () {
    final message = PushMessage.fromPayload('not json');
    expect(message.id, isNull);
    expect(message.data, isEmpty);
  });

  test('null payload gives an empty message', () {
    expect(PushMessage.fromPayload(null).route, isNull);
  });
}
