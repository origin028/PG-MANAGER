import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../core/network_service.dart';
import '../models/payment.dart';

enum PaymentFlowState { idle, initiating, awaitingCheckout, verifying, success, failed }

class PaymentProvider with ChangeNotifier {
  final NetworkService _networkService = NetworkService();
  late Razorpay _razorpay;

  PaymentFlowState _flowState = PaymentFlowState.idle;
  PaymentRequestResponse? _activePaymentRequest;
  PaymentStatus? _latestStatus;
  String? _errorMessage;

  PaymentFlowState get flowState => _flowState;
  PaymentRequestResponse? get activePaymentRequest => _activePaymentRequest;
  PaymentStatus? get latestStatus => _latestStatus;
  String? get errorMessage => _errorMessage;

  // Callback to signal UI when payment outcome is determined
  Function(PaymentStatus status)? onPaymentComplete;
  Function(String error)? onPaymentError;

  PaymentProvider() {
    _initRazorpay();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  /// 1. Initiates payment with backend to create Razorpay Order & Payment record
  Future<PaymentRequestResponse?> initiatePayment({
    required String invoiceId,
    required double amount,
  }) async {
    _flowState = PaymentFlowState.initiating;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _networkService.post(
        '/payments',
        body: {
          'invoice_id': invoiceId,
          'amount': amount,
          'payment_mode': 'UPI',
        },
      );

      _activePaymentRequest = PaymentRequestResponse.fromJson(data);
      _flowState = PaymentFlowState.awaitingCheckout;
      notifyListeners();
      return _activePaymentRequest;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _flowState = PaymentFlowState.failed;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to initiate payment. Please try again.';
      _flowState = PaymentFlowState.failed;
      notifyListeners();
      return null;
    }
  }

  /// 2. Opens official Razorpay Standard Checkout modal
  void openRazorpayCheckout({
    required PaymentRequestResponse paymentRequest,
    Function(PaymentStatus status)? onComplete,
    Function(String error)? onError,
  }) {
    _activePaymentRequest = paymentRequest;
    onPaymentComplete = onComplete;
    onPaymentError = onError;
    _flowState = PaymentFlowState.awaitingCheckout;
    notifyListeners();

    final options = {
      'key': paymentRequest.keyId,
      'amount': paymentRequest.amountPaise,
      'name': paymentRequest.propertyName ?? 'PG Rent Payment',
      'description': paymentRequest.description ?? 'Rent Payment',
      'order_id': paymentRequest.gatewayOrderId,
      'prefill': {
        'contact': paymentRequest.residentPhone ?? '',
        'email': paymentRequest.residentEmail ?? '',
        'name': paymentRequest.residentName ?? '',
      },
      'theme': {
        'color': '#1E3A8A',
      },
      'modal': {
        'confirm_close': true,
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      _errorMessage = 'Failed to launch checkout: $e';
      _flowState = PaymentFlowState.failed;
      notifyListeners();
      onError?.call(_errorMessage!);
    }
  }

  /// 3. Handles successful client response from Razorpay
  /// Never trusts client alone: verifies cryptographic HMAC-SHA256 signature on backend
  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    _flowState = PaymentFlowState.verifying;
    notifyListeners();

    if (_activePaymentRequest == null) {
      _errorMessage = 'Active payment session lost.';
      _flowState = PaymentFlowState.failed;
      notifyListeners();
      onPaymentError?.call(_errorMessage!);
      return;
    }

    try {
      final verifyData = await _networkService.post(
        '/payments/verify',
        body: {
          'payment_id': _activePaymentRequest!.paymentId,
          'razorpay_order_id': response.orderId ?? _activePaymentRequest!.gatewayOrderId,
          'razorpay_payment_id': response.paymentId ?? '',
          'razorpay_signature': response.signature ?? '',
        },
      );

      final status = PaymentStatus.fromJson(verifyData);
      _latestStatus = status;
      _flowState = status.isSuccess ? PaymentFlowState.success : PaymentFlowState.failed;
      notifyListeners();
      onPaymentComplete?.call(status);
    } on ApiException catch (e) {
      // If immediate verification fails, poll status endpoint as fallback
      final polledStatus = await checkPaymentStatus(_activePaymentRequest!.paymentId);
      if (polledStatus != null && polledStatus.isSuccess) {
        _latestStatus = polledStatus;
        _flowState = PaymentFlowState.success;
        notifyListeners();
        onPaymentComplete?.call(polledStatus);
      } else {
        _errorMessage = e.message;
        _flowState = PaymentFlowState.failed;
        notifyListeners();
        onPaymentError?.call(_errorMessage!);
      }
    } catch (e) {
      _errorMessage = 'Payment verification encountered an unexpected error.';
      _flowState = PaymentFlowState.failed;
      notifyListeners();
      onPaymentError?.call(_errorMessage!);
    }
  }

  /// 4. Handles payment error/cancellation from Razorpay
  void _handlePaymentError(PaymentFailureResponse response) {
    String msg;
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      msg = 'Payment was cancelled by user.';
    } else {
      msg = response.message ?? 'Payment failed. Please try again.';
    }

    _errorMessage = msg;
    _flowState = PaymentFlowState.failed;
    notifyListeners();
    onPaymentError?.call(msg);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('[PaymentProvider] External wallet selected: ${response.walletName}');
  }

  /// Polling / manual query of payment status
  Future<PaymentStatus?> checkPaymentStatus(String paymentId) async {
    try {
      final data = await _networkService.get('/payments/$paymentId/status');
      final status = PaymentStatus.fromJson(data);
      _latestStatus = status;
      notifyListeners();
      return status;
    } catch (_) {
      return null;
    }
  }

  void reset() {
    _flowState = PaymentFlowState.idle;
    _activePaymentRequest = null;
    _latestStatus = null;
    _errorMessage = null;
    notifyListeners();
  }
}
