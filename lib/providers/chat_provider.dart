import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/hermes_api_service.dart';

enum ChatState { idle, streaming, error }

class ChatProvider extends ChangeNotifier {
  final HermesApiService _api;
  final _uuid = const Uuid();
  final List<ChatSession> _sessions = [];
  final ImagePicker _picker = ImagePicker();

  int _currentIndex = 0;
  ChatState _state = ChatState.idle;
  String? _error;
  String _currentResponse = '';
  String? _attachedImage; // base64 data URI

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
    _attachedImage = null; // clear attachment after sending

    if (text.trim().isNotEmpty) _updateSessionTitle();
    _state = ChatState.streaming;
    _currentResponse = '';
    _error = null;
    notifyListeners();

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

  void cancelStream() {
    _state = ChatState.idle;
    _currentResponse = '';
    notifyListeners();
  }

  void clearError() {
    _error = null;
    if (_state == ChatState.error) _state = ChatState.idle;
    notifyListeners();
  }
}
