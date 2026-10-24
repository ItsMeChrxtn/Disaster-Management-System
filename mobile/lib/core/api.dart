import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Thrown for every failed request. Mirrors the `error.status` / `error.errors`
/// contract of frontend/assets/js/api.js.
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.errors = const {}});

  final String message;
  final int status;
  final Map<String, dynamic> errors;

  @override
  String toString() => message;
}

/// Thin JSON client. All responses use `{success, data}`; errors carry
/// `message` and optional field `errors`.
class Api {
  Api._();

  static final Api instance = Api._();

  static const _tokenKey = 'dm_token';
  static const _userKey = 'dm_user';
  static const _apiUrlKey = 'dm_api_url';

  String baseUrl = AppConfig.defaultApiUrl;
  String? _token;
  Map<String, dynamic>? _user;

  /// Called by the session layer when a request comes back 401.
  void Function()? onUnauthorized;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_apiUrlKey) ?? AppConfig.defaultApiUrl;
    _token = prefs.getString(_tokenKey);
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        _user = jsonDecode(rawUser) as Map<String, dynamic>;
      } catch (_) {
        _user = null;
      }
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiUrlKey, baseUrl);
  }

  Future<void> saveSession(String token, Map<String, dynamic> user) async {
    _token = token;
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<void> clearSession() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'Accept': 'application/json', if (_token != null) 'Authorization': 'Bearer $_token'};

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body ?? {});
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body ?? {});
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    http.Response response;
    try {
      final request = http.Request(method, _uri(path));
      request.headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw ApiException('The server could not be reached. Check your connection and try again.');
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = {'success': false, 'message': 'Invalid server response'};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        await clearSession();
        onUnauthorized?.call();
      }
      final errors = payload['errors'];
      throw ApiException((payload['message'] ?? 'Request failed').toString(), status: response.statusCode, errors: errors is Map<String, dynamic> ? errors : const {});
    }
    return payload['data'];
  }

  /// Raw authenticated download (used for generated reports).
  Future<http.Response> download(String path) async {
    try {
      return await http.get(_uri(path), headers: {if (_token != null) 'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 90));
    } catch (_) {
      throw ApiException('The server could not be reached. Check your connection and try again.');
    }
  }
}
