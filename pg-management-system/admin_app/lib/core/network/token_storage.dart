import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const String _accessTokenKey = 'pg_admin_access_token';
  static const String _refreshTokenKey = 'pg_admin_refresh_token';
  static const String _userProfileKey = 'pg_admin_user_profile';

  static String? _cachedAccessToken;
  static String? _cachedRefreshToken;
  static Map<String, dynamic>? _cachedUserProfile;
  static bool _initialized = false;

  /// Initializes storage and loads cached tokens into memory
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedAccessToken = prefs.getString(_accessTokenKey);
      _cachedRefreshToken = prefs.getString(_refreshTokenKey);
      final userJson = prefs.getString(_userProfileKey);
      if (userJson != null) {
        try {
          _cachedUserProfile = jsonDecode(userJson) as Map<String, dynamic>?;
        } catch (_) {
          _cachedUserProfile = null;
        }
      }
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  /// Ensures storage has been initialized before reading tokens
  static Future<void> ensureInitialized() async {
    if (!_initialized || _cachedAccessToken == null) {
      await init();
    }
  }

  static String? get accessToken => _cachedAccessToken;
  static String? get refreshToken => _cachedRefreshToken;
  static Map<String, dynamic>? get userProfile => _cachedUserProfile;
  static bool get isAuthenticated => _cachedAccessToken != null && _cachedAccessToken!.isNotEmpty;

  /// Checks if the cached access token is expired based on JWT exp claim
  static bool get isAccessTokenExpired {
    final token = _cachedAccessToken;
    if (token == null || token.isEmpty) return true;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      var normalized = base64Url.normalize(parts[1]);
      final payloadStr = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is num) {
        final expTime = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
        // Treat as expired if within 30 seconds of expiry
        return DateTime.now().isAfter(expTime.subtract(const Duration(seconds: 30)));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static String? get userRole {
    final profile = userProfile;
    if (profile == null) return null;
    final role = profile['role'];
    if (role is Map) return role['name']?.toString();
    if (role is String) return role;
    return null;
  }

  static bool get canManageInvoices {
    final role = userRole;
    if (role == null) return true; // Default allow in dev/mock if role not present
    return role == 'SUPER_ADMIN' || role == 'PROPERTY_MANAGER';
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    Map<String, dynamic>? user,
  }) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    if (user != null) _cachedUserProfile = user;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    if (user != null) {
      await prefs.setString(_userProfileKey, jsonEncode(user));
    }
  }

  static Future<void> clear() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedUserProfile = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userProfileKey);
  }
}
