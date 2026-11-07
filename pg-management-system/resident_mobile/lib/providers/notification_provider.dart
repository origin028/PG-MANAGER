import 'package:flutter/foundation.dart';
import '../core/network_service.dart';
import '../models/notification.dart';

class NotificationProvider with ChangeNotifier {
  final NetworkService _networkService = NetworkService();

  List<NotificationItem> _notifications = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<NotificationItem> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.get('/notifications/my');
      if (data is List) {
        _notifications = data.map((item) => NotificationItem.fromJson(item)).toList();
      } else {
        _notifications = [];
      }
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      // If server does not have /notifications/my yet, fallback to empty list without crashing
      _notifications = [];
      _isLoading = false;
      notifyListeners();
    }
  }

  void addNotification(NotificationItem item) {
    _notifications.insert(0, item);
    notifyListeners();
  }
}
