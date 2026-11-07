import 'package:flutter/foundation.dart';
import '../core/network_service.dart';
import '../models/resident_profile.dart';

class ResidentProvider with ChangeNotifier {
  final NetworkService _networkService = NetworkService();

  ResidentProfile? _profile;
  bool _isLoading = false;
  String? _errorMessage;

  ResidentProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchProfile() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.get('/residents/me');
      _profile = ResidentProfile.fromJson(data);
      _isLoading = false;
      notifyListeners();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load profile details.';
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _profile = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
