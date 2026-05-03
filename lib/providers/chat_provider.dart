import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/hermes_api_service.dart';

/// Strip unpaired UTF-16 surrogates that would crash jsonEncode.
String _safeJson(String input) {
  final chars = input.runes.where((r) => r < 0xD800 || r > 0xDFFF).toList();
  return String.fromCharCodes(chars);
}

/// Recursively sanitize all strings in a JSON-serializable value.
dynamic _sanitize(dynamic value) {
  if (value is String) return _safeJson(value);
  if (value is List) return value.map(_sanitize).toList();
  if (value is Map) {
    return value.map((k, v) => MapEntry(_sanitize(k), _sanitize(v)));
  }
  return value;
}

enum ChatState { idle, streaming, error }

class ChatProvider extends ChangeNotifier {
  static const _sessionsFile = 'keryx_sessions.json';

  final HermesApiService _api;
  final _uuid = const Uuid();
  final List<ChatSession> _sessions = [];
  final ImagePicker _picker = ImagePicker();

  int _currentIndex = 0;
  ChatState _state = ChatState.idle;
  String? _error;
  String _currentResponse = '';
  String? _attachedImage;
  bool _loaded = false;
  bool _useRunApi = false;
  String? _currentRunId;
  final List<FileOutput> _pendingFiles = [];

  ChatProvider(this._api) {
    _createNewSession();
  }

  int get currentIndex => _currentIndex;
  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession get currentSession => _sessions[_currentIndex];
  List<ChatMessage> get messages => currentSession.messages;
  ChatState get state => _state;
  String? get error => _error;
  String get currentResponse => _currentResponse;
  bool get isStreaming => _state == ChatState.streaming;
  String? get attachedImage => _attachedImage;
  bool get hasAttachedImage => _attachedImage != null;
  bool get loaded => _loaded;
  /// Use Runs API instead of Chat Completions (enables tool calls & file outputs)
  bool get useRunApi => _useRunApi;
  set useRunApi(bool v) {
    _useRunApi = v;
    notifyListeners();
  }

  String? get currentRunId => _currentRunId;

  // ── Persistence ──

  /// Load sessions from local JSON file. Call once on app start.
  Future<void> loadSessions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_sessionsFile');
      if (!await file.exists()) {
        _createNewSession();
        _loaded = true;
        notifyListeners();
        return;
      }
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      _sessions.clear();
      for (final item in list) {
        _sessions.add(ChatSession.fromPersistJson(item as Map<String, dynamic>));
      }
      if (_sessions.isEmpty) {
        _createNewSession();
      } else {
        _currentIndex = 0;
      }
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load sessions: $e');
      _createNewSession();
      _loaded = true;
      notifyListeners();
    }
  }

  /// Save all sessions to local JSON file.
  Future<void> _saveSessions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_sessionsFile');
      final json = jsonEncode(_sanitize(_sessions.map((s) => s.toPersistJson()).toList()));
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('Failed to save sessions: $e');
    }
  }

  // ── Image Attachment ──

  void clearAttachedImage() {
    _attachedImage = null;
    notifyListeners();
  }

  Future<void> pickImageFromGallery() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (xfile == null) return;
      await _encodeImage(xfile.path);
    } catch (e) {
      _error = 'Failed to pick image: $e';
      notifyListeners();
    }
  }

  Future<void> pickImageFromCamera() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (xfile == null) return;
      await _encodeImage(xfile.path);
    } catch (e) {
      _error = 'Failed to take photo: $e';
      notifyListeners();
    }
  }

  Future<void> _encodeImage(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final ext = path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    _attachedImage = 'data:$mime;base64,${base64Encode(bytes)}';
    notifyListeners();
  }

  // ── Session Management ──

  void _createNewSession() {
    final session = ChatSession(id: _uuid.v4(), title: 'New Chat');
    _sessions.add(session);
    _currentIndex = _sessions.length - 1;
    _api.resetSession();
    _saveSessions();
  }

  void createNewSession() {
    _createNewSession();
    _state = ChatState.idle;
    _error = null;
    _currentResponse = '';
    _attachedImage = null;
    notifyListeners();
  }

  void switchToSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _currentIndex = index;
    _state = ChatState.idle;
    _error = null;
    _currentResponse = '';
    _attachedImage = null;
    _api.sessionId = null;
    notifyListeners();
  }

  void _updateSessionTitle() {
    final firstUserMsg = messages.firstWhere(
      (m) => m.isUser,
      orElse: () => messages.first,
    );
    final title = firstUserMsg.content.replaceAll(RegExp(r'\s+'), ' ');
    final trimmed =
        title.length > 40 ? '${title.substring(0, 40)}...' : title;
    _sessions[_currentIndex] = currentSession.copyWith(title: trimmed);
  }

  // ── Send Messages ──

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty && _attachedImage == null) return;
    if (_state == ChatState.streaming) return;

    // Build user message with optional image
    final userMsg = ChatMessage(
      role: 'user',
      content: text.trim(),
      imageDataUri: _attachedImage,
    );
    _sessions[_currentIndex] = currentSession.copyWith(
      messages: [...messages, userMsg],
    );
    _attachedImage = null;

    if (text.trim().isNotEmpty) _updateSessionTitle();
    _state = ChatState.streaming;
    _currentResponse = '';
    _error = null;
    notifyListeners();
    _saveSessions();

    if (_useRunApi) {
      await _sendMessageRun(userMsg);
    } else {
      await _sendMessageChat(userMsg);
    }
  }

  /// Standard Chat Completions (streaming)
  Future<void> _sendMessageChat(ChatMessage userMsg) async {
    try {
      final apiMessages = [
        ...messages.take(messages.length - 1).map((m) => m.toJson()),
        userMsg.toJson(),
      ];

      final buffer = StringBuffer();
      await for (final chunk in _api.chatCompletionsStream(
        messages: apiMessages,
      )) {
        buffer.write(chunk);
        _currentResponse = buffer.toString();
        notifyListeners();
      }

      final assistantMsg = ChatMessage(role: 'assistant', content: _currentResponse);
      _sessions[_currentIndex] = currentSession.copyWith(
        messages: [...messages, assistantMsg],
      );

      _state = ChatState.idle;
      _currentResponse = '';
      notifyListeners();
      _saveSessions();
    } on ApiException catch (e) {
      _error = e.message;
      _state = ChatState.error;
      notifyListeners();
    } catch (e) {
      _error = 'Error: $e';
      _state = ChatState.error;
      notifyListeners();
    }
  }

  /// Runs API (enables tool calls, file outputs)
  Future<void> _sendMessageRun(ChatMessage userMsg) async {
    try {
      // Use full messages array as input (not flattened)
      final messagesInput = [
        ...messages.take(messages.length - 1).map((m) => m.toJson()),
        userMsg.toJson(),
      ];

      // Start the run
      _currentRunId = await _api.startRun(messages: messagesInput);
      _pendingFiles.clear();
      final buffer = StringBuffer();

      // Stream events
      await for (final event in _api.runEventStream(_currentRunId!)) {
        final data = event['data']!;
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final innerEvent = json['event'] as String?;

          // ── Streaming text delta ──
          if (innerEvent == 'message.delta') {
            final delta = json['delta'] as String? ?? '';
            if (delta.isNotEmpty) {
              buffer.write(delta);
              _currentResponse = buffer.toString();
              notifyListeners();
            }
          }

          // ── Final reasoning text (full output) ──
          if (innerEvent == 'reasoning.available') {
            final text = json['text'] as String? ?? '';
            if (text.isNotEmpty && buffer.isEmpty) {
              // Only use if we got no deltas (safety net)
              buffer.write(text);
              _currentResponse = buffer.toString();
              notifyListeners();
            }
          }

          // ── Run completed ──
          if (innerEvent == 'run.completed') {
            final output = json['output'] as String? ?? '';
            if (output.isNotEmpty && buffer.isEmpty) {
              buffer.write(output);
              _currentResponse = buffer.toString();
              notifyListeners();
            }
            break; // Done!
          }

          // ── Tool calls — show as italic context ──
          if (innerEvent == 'tool_call' || json['type'] == 'tool_call') {
            final toolName = json['tool'] as String? ?? json['name'] as String? ?? 'unknown';
            buffer.write('\n\n_🔧 Using **$toolName**..._\n\n');
            _currentResponse = buffer.toString();
            notifyListeners();
          }

          // ── File outputs ──
          if (innerEvent == 'file' || json['type'] == 'file') {
            _pendingFiles.add(FileOutput(
              url: json['url'] as String? ?? json['path'] as String? ?? '',
              name: json['name'] as String?,
              mimeType: json['mimeType'] as String? ?? json['mime_type'] as String?,
              size: json['size'] as int?,
            ));
          }
        } catch (_) {
          // Skip unparseable events
        }
      }

      // Create assistant message with accumulated text + files
      final assistantMsg = ChatMessage(
        role: 'assistant',
        content: buffer.toString(),
        files: List.from(_pendingFiles),
      );
      _sessions[_currentIndex] = currentSession.copyWith(
        messages: [...messages, assistantMsg],
      );

      _state = ChatState.idle;
      _currentResponse = '';
      _currentRunId = null;
      _pendingFiles.clear();
      notifyListeners();
      _saveSessions();
    } on ApiException catch (e) {
      _error = e.message;
      _state = ChatState.error;
      _currentRunId = null;
      notifyListeners();
    } catch (e) {
      _error = 'Error: $e';
      _state = ChatState.error;
      _currentRunId = null;
      notifyListeners();
    }
  }

  void cancelStream() {
    _state = ChatState.idle;
    _currentResponse = '';
    _currentRunId = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    if (_state == ChatState.error) _state = ChatState.idle;
    notifyListeners();
  }

  /// Delete the current session and switch to another one.
  void deleteCurrentSession() {
    if (_sessions.length <= 1) {
      // Last session — just clear it instead of deleting
      _sessions[_currentIndex] = ChatSession(
        id: _uuid.v4(),
        title: 'New Chat',
      );
      _api.resetSession();
      notifyListeners();
      _saveSessions();
      return;
    }
    _sessions.removeAt(_currentIndex);
    if (_currentIndex >= _sessions.length) {
      _currentIndex = _sessions.length - 1;
    }
    _api.resetSession();
    _state = ChatState.idle;
    _error = null;
    _currentResponse = '';
    notifyListeners();
    _saveSessions();
  }

  /// Delete all sessions and start fresh.
  Future<void> clearAllSessions() async {
    _sessions.clear();
    _createNewSession();
    _state = ChatState.idle;
    _error = null;
    _currentResponse = '';
    _attachedImage = null;
    _api.resetSession();
    notifyListeners();

    // Also delete the file to reset storage
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_sessionsFile');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
