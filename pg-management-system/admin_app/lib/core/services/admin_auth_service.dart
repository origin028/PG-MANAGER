import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../network/token_storage.dart';

class AdminAuthService {
  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String businessName,
    required String email,
    required String password,
    required String confirmPassword,
    required String superKey,
    String? fullName,
    String? phone,
  })? registerHandler;

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String email,
    required String password,
  })? loginHandler;

  /// Admin Login using Email and Password only. Directly receives and saves JWT tokens.
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    if (loginHandler != null) {
      return await loginHandler!(email: email, password: password);
    }

    final response = await ApiClient.post(
      '/auth/admin/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password.trim(),
      },
    );

    if (response is Map<String, dynamic>) {
      final accessToken = response['access_token']?.toString() ?? '';
      final refreshToken = response['refresh_token']?.toString() ?? '';
      final user = response['user'] as Map<String, dynamic>?;

      if (accessToken.isNotEmpty) {
        await TokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          user: user,
        );
      }
      return response;
    }
    return <String, dynamic>{};
  }

  /// Verifies Super Key 2FA (Step 2) and saves JWT tokens.
  static Future<Map<String, dynamic>> verifySuperKey({
    required String email,
    required String superKey,
  }) async {
    final response = await ApiClient.post(
      '/auth/admin/login/verify',
      body: {
        'email': email.trim().toLowerCase(),
        'super_key': superKey.trim(),
      },
    );

    if (response is Map<String, dynamic>) {
      final accessToken = response['access_token']?.toString() ?? '';
      final refreshToken = response['refresh_token']?.toString() ?? '';
      final user = response['user'] as Map<String, dynamic>?;

      if (accessToken.isNotEmpty) {
        await TokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          user: user,
        );
      }
      return response;
    }
    return <String, dynamic>{};
  }

  /// Resends Admin Login Super Key 2FA
  static Future<void> resendSuperKey({required String email}) async {
    await ApiClient.post(
      '/auth/admin/login/resend-otp',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  /// Registers a new PG owner account using Origin Common Super Key.
  static Future<Map<String, dynamic>> register({
    required String businessName,
    required String email,
    required String password,
    required String confirmPassword,
    required String superKey,
    String? fullName,
    String? phone,
  }) async {
    if (registerHandler != null) {
      return await registerHandler!(
        businessName: businessName,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        superKey: superKey,
        fullName: fullName,
        phone: phone,
      );
    }

    final response = await ApiClient.post(
      '/auth/admin/register',
      body: {
        'business_name': businessName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password.trim(),
        'confirm_password': confirmPassword.trim(),
        'super_key': superKey.trim().toUpperCase(),
        if (fullName != null && fullName.isNotEmpty) 'full_name': fullName.trim(),
        if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
      },
    );
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  /// Verifies Registration Super Key to activate owner account.
  static Future<Map<String, dynamic>> verifyRegisterSuperKey({
    required String email,
    required String superKey,
  }) async {
    final response = await ApiClient.post(
      '/auth/admin/register/verify',
      body: {
        'email': email.trim().toLowerCase(),
        'super_key': superKey.trim(),
      },
    );

    if (response is Map<String, dynamic> && response.containsKey('access_token')) {
      final accessToken = response['access_token']?.toString() ?? '';
      final refreshToken = response['refresh_token']?.toString() ?? '';
      final user = response['user'] as Map<String, dynamic>?;
      if (accessToken.isNotEmpty) {
        await TokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          user: user,
        );
      }
    }
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  /// Fetches the profile of the current logged-in user.
  static Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await ApiClient.get('/auth/me');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  /// Revokes refresh token and clears local session.
  static Future<void> logout() async {
    try {
      final refresh = TokenStorage.refreshToken;
      if (refresh != null && refresh.isNotEmpty) {
        await ApiClient.post(
          '/auth/logout',
          body: {'refresh_token': refresh, 'client_type': 'admin_web'},
        );
      }
    } catch (_) {
      // Continue clearing session on error
    } finally {
      await TokenStorage.clear();
    }
  }
}
