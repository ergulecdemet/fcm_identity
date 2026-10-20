import 'package:fcm_identity/fcm_identity.dart';
import 'package:flutter/material.dart';

// Run `flutterfire configure` in this folder first. It creates the native
// config files that Firebase reads when `firebaseOptions` is null. You can
// also import the generated firebase_options.dart and pass
// `DefaultFirebaseOptions.currentPlatform`.

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FcmIdentity.instance.init(
    FcmIdentityConfig(
      registrar: HttpRegistrar(
        registerUrl: Uri.parse('https://api.example.com/devices'),
        headers: () async => {'Authorization': 'Bearer <your-session-token>'},
      ),
      onMessageOpened: (message) {
        final route = message.route;
        if (route != null) navigatorKey.currentState?.pushNamed(route);
      },
      onError: (error, _) => debugPrint('fcm_identity error: $error'),
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(navigatorKey: navigatorKey, home: const HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final fcm = FcmIdentity.instance;

  @override
  void initState() {
    super.initState();
    // Handle a notification that opened the app from a terminated state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = fcm.takeInitialMessage();
      if (initial?.route != null) {
        navigatorKey.currentState?.pushNamed(initial!.route!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fcm_identity example')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('User: ${fcm.userId ?? '-'}'),
          const SizedBox(height: 8),
          SelectableText('Token: ${fcm.token ?? '-'}'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              await fcm.requestPermission();
              setState(() {});
            },
            child: const Text('Allow notifications'),
          ),
          FilledButton(
            onPressed: () async {
              await fcm.login('12345', properties: {'plan': 'free'});
              setState(() {});
            },
            child: const Text('Log in as 12345'),
          ),
          OutlinedButton(
            onPressed: () async {
              await fcm.logout();
              setState(() {});
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
