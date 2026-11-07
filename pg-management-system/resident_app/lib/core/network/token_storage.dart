import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const String _accessTokenKey = 'pg_resident_access_token';
  static const String _refreshTokenKey = 'pg_resident_refresh_token';
  static const String _userProfileKey = 'pg_resident_user_profile';
  static const String _residentProfileKey = 'pg_resident_profile';

  static String? _cachedAccessToken;
  static String? _cachedRefreshToken;
  static Map<String, dynamic>? _cachedUserProfile;
  static Map<String, dynamic>? _cachedResidentProfile;
  static bool _initialized = false;

  /// Initializes storage and loads cached tokens into memory
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedAccessToken = prefs.getString(_accessTokenKey);
      _cachedRefreshToken = prefs.getString(_refreshTokenKey);
      final userJson = prefs.getString(_userProfileKey);
      if (userJson != null) {
        _cachedUserProfile = jsonDecode(userJson) as Map<String, dynamic>?;
      }
      final residentJson = prefs.getString(_residentProfileKey);
      if (residentJson != null) {
        _cachedResidentProfile = jsonDecode(residentJson) as Map<String, dynamic>?;
      }
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  static String? get accessToken => _cachedAccessToken;
  static String? get refreshToken => _cachedRefreshToken;
  static Map<String, dynamic>? get userProfile => _cachedUserProfile;
  static Map<String, dynamic>? get residentProfile => _cachedResidentProfile;
  static bool get isAuthenticated => _cachedAccessToken != null && _cachedAccessToken!.isNotEmpty;

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

  static Future<void> saveResidentProfile(Map<String, dynamic> profile) async {
    _cachedResidentProfile = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_residentProfileKey, jsonEncode(profile));
  }

  static Future<void> clear() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedUserProfile = null;
    _cachedResidentProfile = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userProfileKey);
    await prefs.remove(_residentProfileKey);
  }
}
