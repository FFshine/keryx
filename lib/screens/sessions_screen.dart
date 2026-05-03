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
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          Consumer<ChatProvider>(
            builder: (context, chat, _) {
              if (chat.sessions.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear all',
                onPressed: () => _confirmClearAll(context, chat),
              );
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chat, _) {
          final sessions = chat.sessions;

          if (!chat.loaded) {
            return const Center(child: CircularProgressIndicator());
          }

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
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      chat.createNewSession();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Start a chat'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final isActive = index == chat.currentIndex;
              final time = _formatTime(session.updatedAt);

              return Dismissible(
                key: ValueKey(session.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: colorScheme.errorContainer,
                  child: Icon(Icons.delete_outline, color: colorScheme.error),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete session?'),
                      content: Text(session.title),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'Delete',
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (_) {
                  final wasActive = isActive;
                  chat.switchToSession(wasActive
                      ? (index > 0 ? index - 1 : 0)
                      : chat.currentIndex);
                  if (wasActive) chat.switchToSession(index.clamp(0, chat.sessions.length - 1));
                  chat.deleteCurrentSession();
                },
                child: Card(
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
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${session.messageCount} msgs · $time'
                          '${session.messageCount > 0 ? " · ${session.preview}" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: isActive
                        ? Icon(Icons.check, color: colorScheme.primary, size: 18)
                        : Icon(Icons.chevron_right,
                            color: colorScheme.outline, size: 18),
                    onTap: () {
                      chat.switchToSession(index);
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmClearAll(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all sessions?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              chat.clearAllSessions();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(
              'Clear All',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
