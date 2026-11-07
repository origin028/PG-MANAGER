import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pushy_flutter/pushy_flutter.dart';
import 'network_service.dart';

class PushyService {
  static final PushyService _instance = PushyService._internal();
  factory PushyService() => _instance;
  PushyService._internal();

  static final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNotificationTapped =>
      _notificationTapController.stream;

  bool _initialized = false;
  String? deviceToken;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Start Pushy notification listener service
      Pushy.listen();

      // Listen for incoming notifications when app is in foreground
      Pushy.setNotificationListener((Map<String, dynamic> data) {
        debugPrint('[Pushy] Foreground Notification: $data');
      });

      // Listen for notification taps
      Pushy.setNotificationClickListener((Map<String, dynamic> data) {
        debugPrint('[Pushy] Notification Clicked: $data');
        _notificationTapController.add(data);
      });
    } catch (e) {
      debugPrint('[Pushy] Listener setup warning: $e');
    }
  }

  Future<String?> registerDevice() async {
    try {
      // Request device token from Pushy
      final token = await Pushy.register();
      deviceToken = token;
      debugPrint('[Pushy] Device token registered: $token');

      // Dispatch token to our authenticated backend endpoint
      await _sendTokenToBackend(token);
      return token;
    } catch (e) {
      debugPrint('[Pushy] Registration warning (may occur on emulator or unsupported environment): $e');
      return null;
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await NetworkService().post(
        '/notifications/device-token',
        body: {
          'device_token': token,
          'platform': 'android',
          'device_name': defaultTargetPlatform.name,
        },
      );
      debugPrint('[Pushy] Device token successfully linked to resident account on backend.');
    } catch (e) {
      debugPrint('[Pushy] Failed to upload token to backend: $e');
    }
  }
}
