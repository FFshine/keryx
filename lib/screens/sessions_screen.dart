import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: Consumer<ChatProvider>(
        builder: (context, chat, _) {
          final sessions = chat.sessions;

          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No sessions yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sessions.length + 1, // +1 for new chat button
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: FilledButton.icon(
                    onPressed: () {
                      chat.createNewSession();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Chat'),
                  ),
                );
              }

              final session = sessions[index - 1];
              final isActive = index - 1 == _currentIndex(chat);
              final time = _formatTime(session.updatedAt);

              return Card(
                elevation: 0,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: isActive
                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.chat_outlined,
                      color: isActive
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(
                    session.title,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${session.messageCount} msgs · $time',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isActive
                      ? Icon(Icons.check, color: colorScheme.primary, size: 18)
                      : null,
                  onTap: () {
                    chat.switchToSession(index - 1);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  int _currentIndex(ChatProvider chat) {
    return chat.currentIndex;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
