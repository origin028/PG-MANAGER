import 'package:flutter/foundation.dart';
import '../core/network_service.dart';
import '../core/pushy_service.dart';
import '../core/secure_storage.dart';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  final NetworkService _networkService = NetworkService();
  final PushyService _pushyService = PushyService();

  User? _user;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    _networkService.onSessionExpired = () {
      _isAuthenticated = false;
      _user = null;
      notifyListeners();
    };
  }

  Future<bool> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await StorageService.getAccessToken();
      if (token == null || token.isEmpty) {
        _isAuthenticated = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Validate session with backend /auth/me
      final data = await _networkService.get('/auth/me');
      if (data != null) {
        _user = User.fromJson(data);
        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();

        // Register Pushy notifications in background
        _pushyService.registerDevice();
        return true;
      }
    } catch (_) {
      // If error (or 401), session expired or offline
      await StorageService.clearAll();
      _isAuthenticated = false;
      _user = null;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> login(String identifier, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.post(
        '/auth/login',
        authenticated: false,
        body: {
          'identifier': identifier.trim(),
          'password': password,
          'client_type': 'resident_mobile',
        },
      );

      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String;
      final userData = data['user'] as Map<String, dynamic>;

      _user = User.fromJson(userData);

      // Verify resident role
      if (_user!.roleName.toUpperCase() != 'RESIDENT') {
        _errorMessage = 'Access denied. Only registered residents may log in to this app.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await StorageService.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: _user!.id,
      );

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();

      // Register Pushy notifications in background
      _pushyService.registerDevice();

      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await StorageService.clearAll();
    _user = null;
    _isAuthenticated = false;
    _errorMessage = null;

    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
