import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'providers/connection_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      child: const KeryxApp(),
    ),
  );
}

class KeryxApp extends StatelessWidget {
  const KeryxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keryx',
      debugShowCheckedModeBanner: false,
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
      initialRoute: '/setup',
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
