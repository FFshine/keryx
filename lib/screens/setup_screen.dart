import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late TextEditingController _urlController;
  late TextEditingController _keyController;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    final conn = context.read<ConnectionProvider>();
    _urlController = TextEditingController(text: conn.baseUrl);
    _keyController = TextEditingController(text: conn.apiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final conn = context.read<ConnectionProvider>();
    final success = await conn.connect(
      url: _urlController.text.trim(),
      apiKey: _keyController.text.trim(),
    );
    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/chat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo area
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    Icons.flash_on_rounded,
                    size: 52,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Keryx',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hermes Agent Mobile Client',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),

                // Server URL
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://127.0.0.1:8642',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // API Key
                TextField(
                  controller: _keyController,
                  obscureText: !_showKey,
                  decoration: InputDecoration(
                    labelText: 'API Key (optional)',
                    hintText: 'Leave blank if no auth',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 32),

                // Connect button
                Consumer<ConnectionProvider>(
                  builder: (context, conn, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: conn.connecting ? null : _connect,
                        icon: conn.connecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.link),
                        label: Text(
                          conn.connecting ? 'Connecting...' : 'Connect',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Error message
                Consumer<ConnectionProvider>(
                  builder: (context, conn, _) {
                    if (conn.error == null) return const SizedBox.shrink();
                    return Card(
                      elevation: 0,
                      color: colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                conn.error!,
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
