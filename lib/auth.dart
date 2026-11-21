import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SavedSession {
  const SavedSession({required this.serverUrl, required this.token});

  final String serverUrl;
  final String token;
}

abstract interface class AuthRepository {
  Future<SavedSession?> loadSession();
  Future<void> checkConnection(String serverUrl);
  Future<SavedSession> login(String serverUrl, String username, String password);
  Future<void> logout(SavedSession session);
  Future<String?> loadEntriesCache(String serverUrl);
  Future<void> saveEntriesCache(String serverUrl, String json);

  Future<List<Map<String, dynamic>>> loadEntries(SavedSession session) async =>
      throw UnimplementedError();
  Future<Map<String, dynamic>> createEntry(
    SavedSession session,
    Map<String, Object?> entry,
  ) async => throw UnimplementedError();
  Future<void> deleteEntry(SavedSession session, int id) async =>
      throw UnimplementedError();
  Future<Map<String, dynamic>> loadSummary(SavedSession session) async =>
      throw UnimplementedError();
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ServerAuthRepository implements AuthRepository {
  ServerAuthRepository({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
  })  : _client = client ?? http.Client(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _serverUrlKey = 'piggylog.server_url';
  static const _tokenKey = 'piggylog.session_token';
  static const _cacheKeyPrefix = 'piggylog.entries.';

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  Uri _serverUri(String value, String path) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        !parsed.hasScheme ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty) {
      throw const ApiException('Masukkan URL server yang valid, termasuk http:// atau https://.');
    }

    final basePath = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    return parsed.replace(path: '$basePath$path');
  }

  Future<http.Response> _request(
    String serverUrl,
    String path, {
    String? token,
    Map<String, String>? headers,
    Object? body,
    String method = 'GET',
  }) {
    final uri = _serverUri(serverUrl, path);
    final requestHeaders = <String, String>{
      if (body != null) 'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      ...?headers,
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'POST' => _client.post(uri, headers: requestHeaders, body: encodedBody).timeout(const Duration(seconds: 8)),
      'DELETE' => _client.delete(uri, headers: requestHeaders).timeout(const Duration(seconds: 8)),
      _ => _client.get(uri, headers: requestHeaders).timeout(const Duration(seconds: 8)),
    };
  }

  @override
  Future<void> checkConnection(String serverUrl) async {
    final response = await _request(serverUrl, '/health');
    if (response.statusCode != 200) {
      throw const ApiException('Server ditemukan, tetapi bukan PiggyLog API yang valid.');
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['ok'] != true) {
        throw const ApiException('Server ditemukan, tetapi bukan PiggyLog API yang valid.');
      }
    } on FormatException {
      throw const ApiException('Server mengirim respons yang tidak valid.');
    } on TypeError {
      throw const ApiException('Server mengirim respons yang tidak valid.');
    }
  }

  @override
  Future<SavedSession> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    final response = await _request(
      serverUrl,
      '/auth/login',
      method: 'POST',
      body: {'username': username, 'password': password},
    );
    if (response.statusCode == 401) {
      throw const ApiException('Username atau password salah.');
    }
    if (response.statusCode != 200) {
      throw ApiException('Login gagal (HTTP ${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ApiException('Respons login tidak berisi session yang valid.');
    }

    final normalizedUrl = _normalizedServerUrl(serverUrl);
    final preferences = await _preferences;
    await preferences.setString(_serverUrlKey, normalizedUrl);
    await _secureStorage.write(key: _tokenKey, value: token);
    return SavedSession(serverUrl: normalizedUrl, token: token);
  }

  @override
  Future<SavedSession?> loadSession() async {
    final preferences = await _preferences;
    final serverUrl = preferences.getString(_serverUrlKey);
    final token = await _secureStorage.read(key: _tokenKey);
    if (serverUrl == null || token == null || token.isEmpty) return null;
    return SavedSession(serverUrl: serverUrl, token: token);
  }

  @override
  Future<void> logout(SavedSession session) async {
    try {
      final response = await _request(
        session.serverUrl,
        '/auth/session',
        token: session.token,
        method: 'DELETE',
      );
      if (response.statusCode != 204 && response.statusCode != 401) {
        throw ApiException('Server gagal mengakhiri session (HTTP ${response.statusCode}).');
      }
    } finally {
      final preferences = await _preferences;
      await preferences.remove(_serverUrlKey);
      await _secureStorage.delete(key: _tokenKey);
    }
  }

  @override
  Future<String?> loadEntriesCache(String serverUrl) async {
    final preferences = await _preferences;
    return preferences.getString('$_cacheKeyPrefix${_cacheKey(serverUrl)}');
  }

  @override
  Future<void> saveEntriesCache(String serverUrl, String json) async {
    final preferences = await _preferences;
    await preferences.setString('$_cacheKeyPrefix${_cacheKey(serverUrl)}', json);
  }

  Future<Map<String, dynamic>> _jsonRequest(
    SavedSession session,
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final response = await _request(
      session.serverUrl,
      path,
      token: session.token,
      method: method,
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Permintaan gagal (HTTP ${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> loadEntries(SavedSession session) async {
    final response = await _request(session.serverUrl, '/api/v1/entries', token: session.token);
    if (response.statusCode != 200) {
      throw ApiException('Gagal memuat tabungan (HTTP ${response.statusCode}).');
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> createEntry(
    SavedSession session,
    Map<String, Object?> entry,
  ) => _jsonRequest(session, '/api/v1/entries', method: 'POST', body: entry);

  @override
  Future<void> deleteEntry(SavedSession session, int id) async {
    final response = await _request(
      session.serverUrl,
      '/api/v1/entries/$id',
      token: session.token,
      method: 'DELETE',
    );
    if (response.statusCode != 204) {
      throw ApiException('Gagal menghapus tabungan (HTTP ${response.statusCode}).');
    }
  }

  @override
  Future<Map<String, dynamic>> loadSummary(SavedSession session) =>
      _jsonRequest(session, '/api/v1/summary');

  String _normalizedServerUrl(String serverUrl) {
    final uri = _serverUri(serverUrl, '');
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: path).toString().replaceFirst(RegExp(r'/+$'), '');
  }

  String _cacheKey(String serverUrl) =>
      base64Url.encode(utf8.encode(_normalizedServerUrl(serverUrl)));
}
