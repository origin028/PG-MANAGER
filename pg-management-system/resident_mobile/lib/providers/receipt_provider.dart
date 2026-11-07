import 'package:flutter/foundation.dart';
import '../core/network_service.dart';
import '../models/receipt.dart';

class ReceiptProvider with ChangeNotifier {
  final NetworkService _networkService = NetworkService();

  List<ReceiptSummary> _receipts = [];
  ReceiptDetail? _selectedReceipt;
  bool _isLoading = false;
  String? _errorMessage;

  List<ReceiptSummary> get receipts => _receipts;
  ReceiptDetail? get selectedReceipt => _selectedReceipt;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchReceipts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.get('/receipts/my');
      if (data is List) {
        _receipts = data.map((item) => ReceiptSummary.fromJson(item)).toList();
      } else {
        _receipts = [];
      }
      _isLoading = false;
      notifyListeners();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load receipts.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<ReceiptDetail?> fetchReceiptDetail(String receiptId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.get('/receipts/$receiptId');
      _selectedReceipt = ReceiptDetail.fromJson(data);
      _isLoading = false;
      notifyListeners();
      return _selectedReceipt;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to load receipt details.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  void clearSelectedReceipt() {
    _selectedReceipt = null;
    notifyListeners();
  }
}
