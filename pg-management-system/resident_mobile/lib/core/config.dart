import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _storageKey = 'custom_api_base_url';
  static const String _defaultEmulatorUrl = 'http://10.0.2.2:8000/api/v1';
  static const String _defaultLocalhostUrl = 'http://127.0.0.1:8000/api/v1';

  static String baseUrl = _resolveDefaultBaseUrl();

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_storageKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        baseUrl = savedUrl;
      }
    } catch (_) {}
  }

  static String _resolveDefaultBaseUrl() {
    if (kIsWeb) {
      return _defaultLocalhostUrl;
    }
    if (Platform.isAndroid) {
      return _defaultEmulatorUrl;
    }
    return _defaultLocalhostUrl;
  }

  static Future<void> setCustomBaseUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    baseUrl = cleanUrl;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, cleanUrl);
    } catch (_) {}
  }
}
