import 'dart:convert';
import 'dart:typed_data';

class ChatMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final String? imageDataUri;
  final DateTime timestamp;

  Uint8List? _cachedImageBytes;

  ChatMessage({
    required this.role,
    required this.content,
    this.imageDataUri,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Lazy-decoded image bytes — cached after first decode
  Uint8List? get imageBytes {
    if (imageDataUri == null) return null;
    if (_cachedImageBytes != null) return _cachedImageBytes;
    final comma = imageDataUri!.indexOf(',');
    if (comma == -1) return null;
    try {
      _cachedImageBytes = base64.decode(imageDataUri!.substring(comma + 1));
      return _cachedImageBytes;
    } catch (_) {
      return null;
    }
  }

  // ── Hermes API JSON ──

  /// JSON for Hermes API — returns simple string or multi-part array
  dynamic toApiJson() {
    if (imageDataUri == null) return content;
    return [
      {'type': 'text', 'text': content},
      {
        'type': 'image_url',
        'image_url': {'url': imageDataUri},
      },
    ];
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': toApiJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
      );

  // ── Persistence JSON (saves all fields) ──

  Map<String, dynamic> toPersistJson() => {
        'role': role,
        'content': content,
        if (imageDataUri != null) 'imageDataUri': imageDataUri,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromPersistJson(Map<String, dynamic> json) =>
      ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        imageDataUri: json['imageDataUri'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  ChatMessage copyWith({
    String? content,
    String? role,
    String? imageDataUri,
  }) =>
      ChatMessage(
        role: role ?? this.role,
        content: content ?? this.content,
        imageDataUri: imageDataUri ?? this.imageDataUri,
        timestamp: timestamp,
      );

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';
  bool get hasImage => imageDataUri != null;
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    this.title = 'New Chat',
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get messageCount => messages.length;
  String get preview {
    if (messages.isEmpty) return 'Empty session';
    final last = messages.last;
    final text = last.content.replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 60 ? '${text.substring(0, 60)}...' : text;
  }

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ChatSession(
        id: id ?? this.id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  // ── Persistence JSON ──

  Map<String, dynamic> toPersistJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toPersistJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatSession.fromPersistJson(Map<String, dynamic> json) {
    final msgs = (json['messages'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map((m) => ChatMessage.fromPersistJson(m))
            .toList() ??
        [];
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'New Chat',
      messages: msgs,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}
