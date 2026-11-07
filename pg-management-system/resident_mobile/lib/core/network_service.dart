import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'secure_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;

  ApiException({
    required this.statusCode,
    required this.message,
    this.details,
  });

  @override
  String toString() => message;
}

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  Function()? onSessionExpired;

  Future<Map<String, String>> _getHeaders({bool authenticated = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (authenticated) {
      final token = await StorageService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<dynamic> get(String endpoint, {bool authenticated = true}) async {
    return _sendWithRetry(() async {
      final headers = await _getHeaders(authenticated: authenticated);
      final url = Uri.parse('${AppConfig.baseUrl}$endpoint');
      return await http.get(url, headers: headers);
    }, authenticated: authenticated);
  }

  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    return _sendWithRetry(() async {
      final headers = await _getHeaders(authenticated: authenticated);
      final url = Uri.parse('${AppConfig.baseUrl}$endpoint');
      return await http.post(
        url,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    }, authenticated: authenticated);
  }

  Future<dynamic> _sendWithRetry(
    Future<http.Response> Function() requestFn, {
    required bool authenticated,
  }) async {
    http.Response response;
    try {
      response = await requestFn();
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'Network connection failed. Please check your internet or server settings.',
      );
    }

    if (response.statusCode == 401 && authenticated) {
      // Attempt token refresh
      final refreshed = await _attemptTokenRefresh();
      if (refreshed) {
        try {
          response = await requestFn();
        } catch (e) {
          throw ApiException(
            statusCode: 0,
            message: 'Network error during retried request.',
          );
        }
      } else {
        await StorageService.clearAll();
        onSessionExpired?.call();
        throw ApiException(
          statusCode: 401,
          message: 'Your session has expired. Please log in again.',
        );
      }
    }

    return _processResponse(response);
  }

  Future<bool> _attemptTokenRefresh() async {
    final refreshToken = await StorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final url = Uri.parse('${AppConfig.baseUrl}/auth/refresh');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'refresh_token': refreshToken,
          'client_type': 'resident_mobile',
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tokenData = data['data'];
        await StorageService.saveTokens(
          accessToken: tokenData['access_token'],
          refreshToken: tokenData['refresh_token'],
          userId: tokenData['user']?['id'],
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  dynamic _processResponse(http.Response response) {
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

    String errorMessage = 'Server error (${response.statusCode})';
    if (jsonBody is Map<String, dynamic>) {
      if (jsonBody['error'] is Map<String, dynamic> &&
          jsonBody['error']['message'] != null) {
        errorMessage = jsonBody['error']['message'];
      } else if (jsonBody['message'] != null) {
        errorMessage = jsonBody['message'];
      } else if (jsonBody['detail'] != null) {
        errorMessage = jsonBody['detail'].toString();
      }
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: errorMessage,
      details: jsonBody,
    );
  }
}
