import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import 'token_storage.dart';

class ApiClient {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _defaultProdBaseUrl = 'https://pg-management-api-sw09.onrender.com/api/v1';

  static String get baseUrl {
    String url;
    if (_envBaseUrl.isNotEmpty) {
      url = _envBaseUrl;
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      url = 'http://10.0.2.2:8000/api/v1';
    } else if (kIsWeb) {
      if (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1') {
        url = 'http://localhost:8000/api/v1';
      } else {
        url = _defaultProdBaseUrl;
      }
    } else {
      url = 'http://localhost:8000/api/v1';
    }
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static const Duration timeout = Duration(seconds: 60);
  static bool _isRefreshing = false;

  /// Ensures storage is initialized and access token is valid before sending request
  static Future<void> _ensureValidToken(String path) async {
    // Skip token validation for unauthenticated auth endpoints
    if (path.startsWith('/auth/admin/login') ||
        path.startsWith('/auth/admin/register') ||
        path.startsWith('/auth/login') ||
        path.startsWith('/auth/register') ||
        path.startsWith('/auth/refresh')) {
      return;
    }

    await TokenStorage.ensureInitialized();

    // If access token is expired or missing, attempt refresh if refresh token exists
    if ((TokenStorage.accessToken == null || TokenStorage.isAccessTokenExpired) &&
        TokenStorage.refreshToken != null &&
        TokenStorage.refreshToken!.isNotEmpty &&
        !_isRefreshing) {
      await _refreshAccessToken();
    }
  }

  /// Refreshes access token using backend /auth/refresh endpoint
  static Future<bool> _refreshAccessToken() async {
    final refreshToken = TokenStorage.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;

    _isRefreshing = true;
    try {
      final uri = Uri.parse('$baseUrl/auth/refresh');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'refresh_token': refreshToken,
          'client_type': 'admin_web',
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final data = body is Map && body.containsKey('data') ? body['data'] : body;
        if (data is Map) {
          final newAccess = data['access_token']?.toString();
          final newRefresh = data['refresh_token']?.toString() ?? refreshToken;
          final user = data['user'] as Map<String, dynamic>?;
          if (newAccess != null && newAccess.isNotEmpty) {
            await TokenStorage.saveTokens(
              accessToken: newAccess,
              refreshToken: newRefresh,
              user: user,
            );
            return true;
          }
        }
      }
    } catch (_) {
      // Refresh failed
    } finally {
      _isRefreshing = false;
    }
    return false;
  }

  static Map<String, String> _buildHeaders([Map<String, String>? extraHeaders]) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = TokenStorage.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  static Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    var cleanPath = path.startsWith('/') ? path : '/$path';
    if (cleanPath.startsWith('/api/v1/')) {
      cleanPath = cleanPath.substring(7);
    }
    final fullUrl = '$baseUrl$cleanPath';
    final uri = Uri.parse(fullUrl);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final cleanParams = <String, String>{};
      queryParameters.forEach((key, value) {
        if (value != null) {
          cleanParams[key] = value.toString();
        }
      });
      return uri.replace(queryParameters: cleanParams);
    }
    return uri;
  }

  static Future<dynamic> _handleResponse(
    http.Response response, {
    Future<dynamic> Function()? retry,
  }) async {
    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(response.body);
    } catch (_) {
      jsonBody = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (jsonBody is Map<String, dynamic> && jsonBody.containsKey('data')) {
        return jsonBody['data'];
      }
      return jsonBody;
    }

    if (response.statusCode == 401) {
      // Attempt token refresh on 401 if refresh token is available and retry callback provided
      if (retry != null &&
          TokenStorage.refreshToken != null &&
          TokenStorage.refreshToken!.isNotEmpty &&
          !_isRefreshing) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          return await retry();
        }
      }
      await TokenStorage.clear();
      throw ApiException.fromResponse(response.statusCode, jsonBody);
    }

    throw ApiException.fromResponse(response.statusCode, jsonBody);
  }

  static Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http.get(uri, headers: _buildHeaders(headers)).timeout(timeout);
      return await _handleResponse(
        response,
        retry: () => get(path, queryParameters: queryParameters, headers: headers),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<http.Response> getRaw(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    try {
      final uri = _buildUri(path, queryParameters);
      return await http.get(uri, headers: _buildHeaders(headers)).timeout(timeout);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<Uint8List> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    final res = await getRaw(path, queryParameters: queryParameters, headers: headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    if (res.statusCode == 401) {
      await TokenStorage.clear();
    }
    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(res.body);
    } catch (_) {}
    throw ApiException.fromResponse(res.statusCode, jsonBody);
  }

  static Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http
          .post(
            uri,
            headers: _buildHeaders(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return await _handleResponse(
        response,
        retry: () => post(path, body: body, queryParameters: queryParameters, headers: headers),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<dynamic> put(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http
          .put(
            uri,
            headers: _buildHeaders(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return await _handleResponse(
        response,
        retry: () => put(path, body: body, queryParameters: queryParameters, headers: headers),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<dynamic> patch(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http
          .patch(
            uri,
            headers: _buildHeaders(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return await _handleResponse(
        response,
        retry: () => patch(path, body: body, queryParameters: queryParameters, headers: headers),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    await _ensureValidToken(path);
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http.delete(uri, headers: _buildHeaders(headers)).timeout(timeout);
      return await _handleResponse(
        response,
        retry: () => delete(path, queryParameters: queryParameters, headers: headers),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }
}
