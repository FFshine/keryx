import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/chat_provider.dart';
import 'providers/connection_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if config exists — determines initial route
  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.containsKey('keryx_base_url');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProxyProvider<ConnectionProvider, ChatProvider>(
          create: (ctx) {
            final chat = ChatProvider(ctx.read<ConnectionProvider>().api);
            chat.loadSessions();
            return chat;
          },
          update: (_, conn, chat) {
            chat ??= ChatProvider(conn.api);
            return chat;
          },
        ),
      ],
      child: KeryxApp(initialRoute: hasConfig ? '/chat' : '/setup'),
    ),
  );
}

class KeryxApp extends StatelessWidget {
  final String initialRoute;

  const KeryxApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keryx',
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/setup':
            return MaterialPageRoute(
              builder: (_) => const SetupScreen(),
              settings: settings,
            );
          case '/chat':
            return MaterialPageRoute(
              builder: (_) => const ChatScreen(),
              settings: settings,
            );
          case '/sessions':
            return MaterialPageRoute(
              builder: (_) => const SessionsScreen(),
              settings: settings,
            );
          case '/settings':
            return MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
              settings: settings,
            );
          default:
            return MaterialPageRoute(
              builder: (_) => const SetupScreen(),
              settings: settings,
            );
        }
      },
    );
  }
}
