import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>>? _models;
  Map<String, dynamic>? _capabilities;
  bool _loadingModels = false;
  String? _modelsError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final conn = context.read<ConnectionProvider>();
    _capabilities = conn.capabilities;
    _loadModels(conn);
  }

  Future<void> _loadModels(ConnectionProvider conn) async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      _models = await conn.api.listModels();
    } catch (e) {
      _modelsError = '$e';
    }
    setState(() => _loadingModels = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection Info
          _SectionHeader(title: 'Connection'),
          Consumer<ConnectionProvider>(
            builder: (context, conn, _) => Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: Icons.dns_outlined,
                      label: 'Server',
                      value: conn.baseUrl,
                    ),
                    const Divider(height: 16),
                    _InfoRow(
                      icon: Icons.vpn_key_outlined,
                      label: 'API Key',
                      value: conn.apiKey.isNotEmpty
                          ? '••••${conn.apiKey.substring(conn.apiKey.length > 8 ? conn.apiKey.length - 8 : 0)}'
                          : 'Not set',
                    ),
                    const Divider(height: 16),
                    _InfoRow(
                      icon: Icons.check_circle_outline,
                      label: 'Status',
                      value: conn.connected ? 'Connected' : 'Disconnected',
                      valueColor: conn.connected
                          ? Colors.green
                          : colorScheme.error,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Capabilities
          if (_capabilities != null) ...[
            _SectionHeader(title: 'Capabilities'),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _capabilities!.entries
                      .where((e) => e.key != 'object' && e.key != 'model_name')
                      .map((e) {
                    final supported = e.value == true;
                    return Chip(
                      avatar: Icon(
                        supported
                            ? Icons.check_circle
                            : Icons.cancel_outlined,
                        size: 18,
                        color: supported ? Colors.green : colorScheme.error,
                      ),
                      label: Text(
                        e.key.replaceAll('supports_', ''),
                        style: theme.textTheme.labelSmall,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Models
          _SectionHeader(title: 'Available Models'),
          if (_loadingModels)
            const Center(child: CircularProgressIndicator())
          else if (_modelsError != null)
            Card(
              elevation: 0,
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _modelsError!,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            )
          else if (_models != null && _models!.isNotEmpty)
            ..._models!.map((m) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    leading: Icon(
                      Icons.smart_toy_outlined,
                      color: colorScheme.primary,
                    ),
                    title: Text(m['id'] as String? ?? 'Unknown'),
                    subtitle: m['owned_by'] != null
                        ? Text('by ${m['owned_by']}')
                        : null,
                    dense: true,
                  ),
                ))
          else
            const Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No models available'),
              ),
            ),
          const SizedBox(height: 24),

          // App Info
          _SectionHeader(title: 'About'),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.flash_on,
                    label: 'Keryx',
                    value: 'v1.0.0',
                  ),
                  const Divider(height: 16),
                  _InfoRow(
                    icon: Icons.link,
                    label: 'Hermes Agent',
                    value: 'OpenAI API Compatible',
                  ),
                  const Divider(height: 16),
                  _InfoRow(
                    icon: Icons.code,
                    label: 'Built with',
                    value: 'Flutter 3.41',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Disconnect button
          Consumer<ConnectionProvider>(
            builder: (context, conn, _) => OutlinedButton.icon(
              onPressed: () async {
                await conn.disconnect();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/setup');
                }
              },
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
