import 'package:flutter/foundation.dart';
import '../core/network_service.dart';
import '../models/invoice.dart';

class InvoiceProvider with ChangeNotifier {
  final NetworkService _networkService = NetworkService();

  List<ResidentInvoiceItem> _invoices = [];
  ResidentInvoiceDetail? _selectedInvoice;
  bool _isLoading = false;
  String? _errorMessage;

  List<ResidentInvoiceItem> get invoices => _invoices;
  ResidentInvoiceDetail? get selectedInvoice => _selectedInvoice;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<ResidentInvoiceItem> get pendingInvoices =>
      _invoices.where((inv) => inv.isPending || inv.isPartiallyPaid || inv.isOverdue).toList();

  List<ResidentInvoiceItem> get paidInvoices =>
      _invoices.where((inv) => inv.isPaid).toList();

  ResidentInvoiceItem? get latestPendingInvoice =>
      pendingInvoices.isNotEmpty ? pendingInvoices.first : null;

  Future<void> fetchInvoices({String? status}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String endpoint = '/invoices/my';
      if (status != null && status.isNotEmpty) {
        endpoint += '?status=$status';
      }
      final data = await _networkService.get(endpoint);
      if (data is List) {
        _invoices = data.map((item) => ResidentInvoiceItem.fromJson(item)).toList();
      } else {
        _invoices = [];
      }
      _isLoading = false;
      notifyListeners();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load invoices.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<ResidentInvoiceDetail?> fetchInvoiceDetail(String invoiceId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.get('/invoices/$invoiceId');
      _selectedInvoice = ResidentInvoiceDetail.fromJson(data);
      _isLoading = false;
      notifyListeners();
      return _selectedInvoice;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to load invoice details.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  void clearSelectedInvoice() {
    _selectedInvoice = null;
    notifyListeners();
  }
}
