import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/hermes_api_service.dart';

class ConnectionProvider extends ChangeNotifier {
  static const _keyBaseUrl = 'keryx_base_url';
  static const _keyApiKey = 'keryx_api_key';

  final HermesApiService _api;
  bool _connected = false;
  bool _connecting = false;
  String? _error;
  Map<String, dynamic>? _capabilities;

  ConnectionProvider()
      : _api = HermesApiService(baseUrl: 'http://10.0.2.2:8642', apiKey: '');

  HermesApiService get api => _api;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get error => _error;
  Map<String, dynamic>? get capabilities => _capabilities;
  String get baseUrl => _api.baseUrl;
  bool get hasApiKey => apiKey.isNotEmpty;
  String get apiKey => _api.apiKey;

  /// Load saved config and auto-connect
  Future<void> loadAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyBaseUrl) ?? 'http://10.0.2.2:8642';
    final key = prefs.getString(_keyApiKey) ?? '';

    _api.baseUrl = url;
    _api.apiKey = key;
    notifyListeners();

    if (url.isNotEmpty) {
      await connect();
    }
  }

  /// Test connection to Hermes server
  Future<bool> connect({String? url, String? apiKey}) async {
    if (url != null) _api.baseUrl = url;
    if (apiKey != null) _api.apiKey = apiKey;

    _connecting = true;
    _error = null;
    notifyListeners();

    try {
      final healthy = await _api.checkHealth();
      if (!healthy) {
        _error = 'Cannot reach Hermes at ${_api.baseUrl}';
        _connecting = false;
        notifyListeners();
        return false;
      }

      // Also check capabilities
      try {
        _capabilities = await _api.getCapabilities();
      } catch (_) {
        // Non-critical
      }

      _connected = true;
      _connecting = false;
      notifyListeners();

      // Save config
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBaseUrl, _api.baseUrl);
      if (_api.apiKey.isNotEmpty) {
        await prefs.setString(_keyApiKey, _api.apiKey);
      }

      return true;
    } catch (e) {
      _error = 'Connection failed: $e';
      _connecting = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect and clear saved config
  Future<void> disconnect() async {
    _connected = false;
    _api.resetSession();
    _capabilities = null;
    notifyListeners();
  }

  /// Clear saved API key without disconnecting
  Future<void> clearSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBaseUrl);
    await prefs.remove(_keyApiKey);
    _api.apiKey = '';
    notifyListeners();
  }
}
