import 'dart:convert';

import 'package:fcm_identity/src/registration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const registration = DeviceRegistration(
    token: 'tok',
    userId: '42',
    platform: 'android',
    properties: {'city': 'gaziantep'},
  );

  test('toJson omits null fields', () {
    const anon = DeviceRegistration(token: 't', platform: 'ios');
    expect(anon.toJson(), {'token': 't', 'platform': 'ios'});
  });

  test('register POSTs JSON with headers', () async {
    late http.Request captured;
    final registrar = HttpRegistrar(
      registerUrl: Uri.parse('https://api.test/devices'),
      headers: () => {'Authorization': 'Bearer abc'},
      client: MockClient((req) async {
        captured = req;
        return http.Response('', 201);
      }),
    );

    await registrar.register(registration);

    expect(captured.method, 'POST');
    expect(captured.headers['Authorization'], 'Bearer abc');
    expect(jsonDecode(captured.body), {
      'token': 'tok',
      'userId': '42',
      'platform': 'android',
      'properties': {'city': 'gaziantep'},
    });
  });

  test('unregister uses DELETE without unregisterUrl', () async {
    late http.Request captured;
    final registrar = HttpRegistrar(
      registerUrl: Uri.parse('https://api.test/devices'),
      client: MockClient((req) async {
        captured = req;
        return http.Response('', 204);
      }),
    );
    await registrar.unregister(registration);
    expect(captured.method, 'DELETE');
  });

  test('unregister POSTs to unregisterUrl when given', () async {
    late http.Request captured;
    final registrar = HttpRegistrar(
      registerUrl: Uri.parse('https://api.test/devices'),
      unregisterUrl: Uri.parse('https://api.test/devices/remove'),
      client: MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      }),
    );
    await registrar.unregister(registration);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/devices/remove');
  });

  test('custom bodyBuilder', () async {
    late http.Request captured;
    final registrar = HttpRegistrar(
      registerUrl: Uri.parse('https://api.test/devices'),
      bodyBuilder: (r) => {'pushToken': r.token},
      client: MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      }),
    );
    await registrar.register(registration);
    expect(jsonDecode(captured.body), {'pushToken': 'tok'});
  });

  test('non-2xx throws RegistrationException', () async {
    final registrar = HttpRegistrar(
      registerUrl: Uri.parse('https://api.test/devices'),
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(
      () => registrar.register(registration),
      throwsA(isA<RegistrationException>()
          .having((e) => e.statusCode, 'statusCode', 500)),
    );
  });
}
