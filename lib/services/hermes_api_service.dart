import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Remove characters that would cause jsonEncode to fail (unpaired surrogates).
String sanitizeJson(String input) {
  final chars = input.runes.where((r) => !_isUnpairedSurrogate(r)).toList();
  return String.fromCharCodes(chars);
}

bool _isUnpairedSurrogate(int rune) => rune >= 0xD800 && rune <= 0xDFFF;

/// Sanitize all string values in a JSON-serializable object recursively.
dynamic _sanitize(dynamic value) {
  if (value is String) return sanitizeJson(value);
  if (value is List) return value.map(_sanitize).toList();
  if (value is Map) {
    return value.map((k, v) => MapEntry(_sanitize(k), _sanitize(v)));
  }
  return value;
}

class HermesApiService {
  String _baseUrl;
  String _apiKey;
  String? _sessionId;

  HermesApiService({
    String baseUrl = 'http://127.0.0.1:8642',
    String apiKey = '',
    String? sessionId,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey,
        _sessionId = sessionId;

  String get baseUrl => _baseUrl;
  String? get sessionId => _sessionId;

  set baseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get apiKey => _apiKey;
  set apiKey(String key) => _apiKey = key;

  set sessionId(String? id) => _sessionId = id;

  void resetSession() => _sessionId = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
        // Only send session header when API key is configured
        if (_sessionId != null && _apiKey.isNotEmpty)
          'X-Hermes-Session-Id': _sessionId!,
      };

  // ── Health Check ──

  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Models ──

  Future<List<Map<String, dynamic>>> listModels() async {
    final uri = Uri.parse('$_baseUrl/v1/models');
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw ApiException('Failed to list models: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map;
    final data = body['data'] as List;
    return data.cast<Map<String, dynamic>>();
  }

  // ── Chat Completions (Streaming SSE) ──

  Stream<String> chatCompletionsStream({
    required List<Map<String, dynamic>> messages,
    String model = 'hermes',
    bool storeSession = true,
  }) async* {
    final uri = Uri.parse('$_baseUrl/v1/chat/completions');
    final body = jsonEncode(_sanitize({
      'model': model,
      'messages': messages,
      'stream': true,
      if (storeSession) ...{
        'store': true,
        'metadata': {'source': 'keryx'},
      },
    }));

    final request = http.Request('POST', uri);
    request.headers.addAll(_headers);
    request.body = body;

    final client = http.Client();

    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 15));

      if (streamed.statusCode != 200) {
        final errorBody = await streamed.stream.bytesToString();
        throw ApiException(
          'API error ${streamed.statusCode}: $errorBody',
        );
      }

      final sessionHeader = streamed.headers['x-hermes-session-id'];
      if (sessionHeader != null && _sessionId == null) {
        _sessionId = sessionHeader;
      }

      await for (final chunk in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!chunk.startsWith('data: ')) continue;
        final data = chunk.substring(6).trim();
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Skip malformed SSE events
        }
      }
    } finally {
      client.close();
    }
  }

  // ── Chat Completions (Non-streaming) ──

  Future<String> chatCompletions({
    required List<Map<String, dynamic>> messages,
    String model = 'hermes',
    bool storeSession = true,
  }) async {
    final uri = Uri.parse('$_baseUrl/v1/chat/completions');
    final body = jsonEncode(_sanitize({
      'model': model,
      'messages': messages,
      'stream': false,
      if (storeSession) ...{
        'store': true,
        'metadata': {'source': 'keryx'},
      },
    }));

    final resp = await http
        .post(uri, headers: _headers, body: body)
        .timeout(const Duration(seconds: 60));

    if (resp.statusCode != 200) {
      throw ApiException('API error ${resp.statusCode}: ${resp.body}');
    }

    // Capture session ID from response headers
    final sessionHeader = resp.headers['x-hermes-session-id'];
    if (sessionHeader != null && _sessionId == null) {
      _sessionId = sessionHeader;
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw ApiException('No response choices');
    }
    final message = choices[0]['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }

  // ── Async Runs ──

  /// Start a run and return the run_id.
  Future<String> startRun({
    required String prompt,
    String? model,
  }) async {
    final uri = Uri.parse('$_baseUrl/v1/runs');
    final body = jsonEncode({
      'messages': [{'role': 'user', 'content': prompt}],
      if (model != null) 'model': model,
    });

    final resp = await http
        .post(uri, headers: _headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 202) {
      throw ApiException('Failed to start run: ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['run_id'] as String;
  }

  /// Get current run status.
  Future<Map<String, dynamic>> getRunStatus(String runId) async {
    final uri = Uri.parse('$_baseUrl/v1/runs/$runId');
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw ApiException('Failed to get run status: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Stop a running run.
  Future<bool> stopRun(String runId) async {
    final uri = Uri.parse('$_baseUrl/v1/runs/$runId/stop');
    final resp = await http
        .post(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    return resp.statusCode == 200;
  }

  /// SSE event stream for a run. Yields raw SSE lines (event + data).
  Stream<Map<String, String>> runEventStream(String runId) async* {
    final uri = Uri.parse('$_baseUrl/v1/runs/$runId/events');
    final request = http.Request('GET', uri);
    request.headers.addAll(_headers);

    final client = http.Client();
    try {
      final streamed = await client.send(request);

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        final colon = line.indexOf(':');
        if (colon == -1) {
          // bare data line — treat as data with no event
          yield {'event': 'data', 'data': line.substring('data:'.length).trim()};
          continue;
        }
        final key = line.substring(0, colon).trim();
        final value = line.substring(colon + 1).trim();
        if (key == 'event') {
          _lastEvent = value;
        } else if (key == 'data') {
          yield {'event': _lastEvent ?? 'data', 'data': value};
          if (value == '[DONE]') break;
        }
      }
    } finally {
      client.close();
      _lastEvent = null;
    }
  }
  String? _lastEvent;

  // ── Capabilities ──

  Future<Map<String, dynamic>> getCapabilities() async {
    final uri = Uri.parse('$_baseUrl/v1/capabilities');
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw ApiException('Failed to get capabilities: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
