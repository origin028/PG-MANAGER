import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import 'token_storage.dart';

class ApiClient {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api/v1';
    }
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      return 'http://$host:8000/api/v1';
    }
    return 'http://localhost:8000/api/v1';
  }

  static const Duration timeout = Duration(seconds: 15);

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
    final cleanPath = path.startsWith('/') ? path : '/$path';
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

  static dynamic _handleResponse(http.Response response) {
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
      TokenStorage.clear();
    }

    throw ApiException.fromResponse(response.statusCode, jsonBody);
  }

  static Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http.get(uri, headers: _buildHeaders(headers)).timeout(timeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<http.Response> getRaw(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      return await http.get(uri, headers: _buildHeaders(headers)).timeout(timeout);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<Uint8List> getBytes(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    final res = await getRaw(path, queryParameters: queryParameters, headers: headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    if (res.statusCode == 401) {
      TokenStorage.clear();
    }
    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(res.body);
    } catch (_) {}
    throw ApiException.fromResponse(res.statusCode, jsonBody);
  }

  static Future<dynamic> post(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http
          .post(
            uri,
            headers: _buildHeaders(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<dynamic> put(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http
          .put(
            uri,
            headers: _buildHeaders(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<dynamic> patch(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http
          .patch(
            uri,
            headers: _buildHeaders(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }

  static Future<dynamic> delete(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await http.delete(uri, headers: _buildHeaders(headers)).timeout(timeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.networkError(e);
    }
  }
}
