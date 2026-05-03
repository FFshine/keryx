import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late TextEditingController _inputController;
  late FocusNode _focusNode;
  final _scrollController = ScrollController();
  final _hasText = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _focusNode = FocusNode();
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final text = _inputController.text;
    _hasText.value = text.trim().isNotEmpty;
    // Hardware keyboard Enter → send message
    if (text.endsWith('\n')) {
      final clean = text.trimRight();
      _inputController.text = '';
      _inputController.selection = TextSelection.collapsed(offset: 0);
      if (clean.isNotEmpty) {
        context.read<ChatProvider>().sendMessage(clean);
      }
    }
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _hasText.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text;
    final chat = context.read<ChatProvider>();
    if (text.trim().isEmpty && !chat.hasAttachedImage) return;

    _inputController.clear();
    _focusNode.requestFocus();

    await chat.sendMessage(text);
    _scrollToBottom();
  }

  void _showAttachOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                context.read<ChatProvider>().pickImageFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                context.read<ChatProvider>().pickImageFromCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChatProvider>(
          builder: (context, chat, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chat.currentSession.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${chat.messages.length} messages',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: () {
              context.read<ChatProvider>().createNewSession();
            },
          ),
          // Sessions / History button — the main entry to see all saved sessions
          Consumer<ChatProvider>(
            builder: (context, chat, _) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'View history',
                  onPressed: () =>
                      Navigator.pushNamed(context, '/sessions'),
                ),
                if (chat.sessions.length > 1)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${chat.sessions.length - 1}',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'sessions':
                  Navigator.pushNamed(context, '/sessions');
                  break;
                case 'settings':
                  Navigator.pushNamed(context, '/settings');
                  break;
                case 'disconnect':
                  context.read<ConnectionProvider>().disconnect();
                  Navigator.pushReplacementNamed(context, '/setup');
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'sessions',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Sessions'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'disconnect',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Disconnect'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chat, _) {
                final msgs = chat.messages;
                final isStreaming = chat.isStreaming;
                final streamText = chat.currentResponse;

                if (!chat.loaded) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (msgs.isEmpty && !isStreaming) {
                  return _buildEmptyState(theme, colorScheme);
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 80),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: msgs.length + (isStreaming ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < msgs.length) {
                      return _MessageBubble(
                        key: ValueKey('msg_${msgs[index].timestamp.millisecondsSinceEpoch}_$index'),
                        message: msgs[index],
                      );
                    }
                    return _MessageBubble(
                      key: const ValueKey('streaming'),
                      message: ChatMessage(
                        role: 'assistant',
                        content: streamText,
                      ),
                      isStreaming: true,
                    );
                  },
                );
              },
            ),
          ),

          // Error banner
          Consumer<ChatProvider>(
            builder: (context, chat, _) {
              if (chat.error == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: colorScheme.errorContainer,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.error!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => chat.clearError(),
                    ),
                  ],
                ),
              );
            },
          ),

          // Image preview above input
          Consumer<ChatProvider>(
            builder: (context, chat, _) {
              if (!chat.hasAttachedImage) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _previewBytes(chat.attachedImage!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Image attached',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => chat.clearAttachedImage(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              );
            },
          ),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            padding: EdgeInsets.only(
              left: 4,
              right: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
              top: 8,
            ),
            child: Row(
              children: [
                // Attach button
                Consumer<ChatProvider>(
                  builder: (context, chat, _) => IconButton(
                    icon: const Icon(Icons.attach_file_outlined),
                    tooltip: 'Attach image',
                    onPressed: chat.isStreaming ? null : _showAttachOptions,
                  ),
                ),
                // Text input
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Message Hermes...',
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<bool>(
                  valueListenable: _hasText,
                  builder: (context, hasText, _) {
                    final chat = context.watch<ChatProvider>();
                    if (chat.isStreaming) {
                      return IconButton.filled(
                        onPressed: () => chat.cancelStream(),
                        icon: const Icon(Icons.stop),
                        tooltip: 'Stop',
                      );
                    }
                    return IconButton.filled(
                      onPressed: (hasText || chat.hasAttachedImage)
                          ? _sendMessage
                          : null,
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: 'Send',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 64,
            color: colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Connected to Hermes Agent',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message or attach an image to start',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Decode a data URI string (data:image/...;base64,...) to bytes
  /// Result is cached in the calling widget via Image.memory.
  static Uint8List _previewBytes(String dataUri) {
    final comma = dataUri.indexOf(',');
    if (comma == -1) return Uint8List(0);
    try {
      return base64.decode(dataUri.substring(comma + 1));
    } catch (_) {
      return Uint8List(0);
    }
  }
}

// ── Message Bubble ──

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;

  const _MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.flash_on_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image in message (user's attached image)
                  if (message.hasImage && message.imageBytes != null) ...[
                    RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: Image.memory(
                              message.imageBytes!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (message.content.isNotEmpty) const SizedBox(height: 8),
                  ],
                  // Text content (rendered as Markdown)
                  if (message.content.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: isStreaming ? 4.0 : 0,
                      ),
                      child: MarkdownBody(
                        data: message.content,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontSize: 14,
                          ),
                          h1: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                          h2: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                          h3: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          strong: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                          em: const TextStyle(fontStyle: FontStyle.italic),
                          code: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            backgroundColor: isUser
                                ? colorScheme.primary.withValues(alpha: 0.3)
                                : colorScheme.surfaceContainerLow,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: isUser
                                ? colorScheme.primary.withValues(alpha: 0.2)
                                : colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: isUser
                                    ? colorScheme.onPrimary.withValues(alpha: 0.4)
                                    : colorScheme.outline,
                                width: 3,
                              ),
                            ),
                          ),
                          listBullet: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                          ),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: isUser
                                    ? colorScheme.onPrimary.withValues(alpha: 0.3)
                                    : colorScheme.outlineVariant,
                                width: 1,
                              ),
                            ),
                          ),
                          a: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          blockSpacing: 6,
                          listIndent: 20,
                          codeblockPadding: EdgeInsets.all(10),
                        ),
                      ),
                    ),
                  if (isStreaming) ...[
                    const SizedBox(height: 4),
                    _TypingDots(color: colorScheme.primary),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary,
              child: Icon(
                Icons.person,
                color: colorScheme.onPrimary,
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Typing Dots ──

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DotsAnimation(
      listenable: _controller,
      color: widget.color,
    );
  }
}

class _DotsAnimation extends AnimatedWidget {
  final Color color;

  const _DotsAnimation({
    required super.listenable,
    required this.color,
  });

  Animation<double> get _animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final delay = i * 0.2;
        final value = ((_animation.value - delay) % 1.0).clamp(0.0, 1.0);
        final size = 4.0 + (value < 0.5 ? value * 6 : (1 - value) * 6);
        return Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        );
      }),
    );
  }
}
