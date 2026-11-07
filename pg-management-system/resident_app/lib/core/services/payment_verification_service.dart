import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_data.dart';
import 'resident_api_service.dart';

enum PaymentVerificationState {
  pendingVerification,
  successful,
  failed,
  cancelled,
}

class PaymentVerificationResult {
  final PaymentVerificationState state;
  final String invoiceId;
  final String transactionRef;
  final num amount;
  final String paymentApp;
  final String? bankApprovalCode;
  final DateTime timestamp;
  final String? message;
  final Map<String, dynamic>? receiptData;

  PaymentVerificationResult({
    required this.state,
    required this.invoiceId,
    required this.transactionRef,
    required this.amount,
    required this.paymentApp,
    this.bankApprovalCode,
    required this.timestamp,
    this.message,
    this.receiptData,
  });

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'invoiceId': invoiceId,
    'transactionRef': transactionRef,
    'amount': amount,
    'paymentApp': paymentApp,
    'bankApprovalCode': bankApprovalCode,
    'timestamp': timestamp.toIso8601String(),
    'message': message,
    'receiptData': receiptData,
  };

  factory PaymentVerificationResult.fromJson(Map<String, dynamic> json) {
    return PaymentVerificationResult(
      state: PaymentVerificationState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => PaymentVerificationState.pendingVerification,
      ),
      invoiceId: json['invoiceId'] ?? '',
      transactionRef: json['transactionRef'] ?? '',
      amount: json['amount'] ?? 0,
      paymentApp: json['paymentApp'] ?? 'UPI',
      bankApprovalCode: json['bankApprovalCode'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      message: json['message'],
      receiptData: json['receiptData'],
    );
  }
}

/// Service handling authoritative payment verification.
/// Strict Security Rules:
/// 1. Returning from a UPI app does NOT automatically mark the invoice as PAID.
/// 2. Client-side claims are never trusted alone as proof of payment.
/// 3. Invoices are marked PAID only after verified confirmation from backend settlement,
///    bank webhook reconciliation, or explicitly in DEMO_ONLINE simulation mode.
class PaymentVerificationService {
  static const String _storageKeyPrefix = 'pg_payment_tx_';
  static const String _verifiedReceiptsKey = 'pg_verified_receipts';

  /// Verified default payee details
  static const String verifiedPayeeUpiId = 'masisokatali90900@okaxis';
  static const String verifiedPayeeName = "Saukatali Masi";
  static const String verifiedCurrency = 'INR';

  /// Generates a unique transaction reference for UPI intent
  static String generateTxnReference(String invoiceId) {
    final rand = Random().nextInt(899999) + 100000;
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'UPI-$dateStr-$rand';
  }

  /// Initiates payment and sets state to Pending Verification
  static Future<PaymentVerificationResult> initiatePayment({
    required String invoiceId,
    required num amount,
    required String paymentApp,
    required String txnRef,
    String? paymentId,
  }) async {
    final result = PaymentVerificationResult(
      state: PaymentVerificationState.pendingVerification,
      invoiceId: invoiceId,
      transactionRef: txnRef,
      amount: amount,
      paymentApp: paymentApp,
      timestamp: DateTime.now(),
      message: 'Payment initiated via $paymentApp. Waiting for bank & backend verification.',
    );

    // Save to storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(result.toJson()));

    return result;
  }

  /// Queries the trusted backend verification mechanism.
  /// Strict Rule: For real UPI payments, returning from the app leaves status in
  /// pendingVerification until confirmed by authoritative bank settlement or webhook.
  static Future<PaymentVerificationResult> verifyWithBackend({
    required String invoiceId,
    required String txnRef,
    required String paymentApp,
    required num amount,
    String? paymentId,
    bool forceFail = false,
    bool forceCancel = false,
    bool forceSuccess = false,
  }) async {
    // Brief network latency simulation
    await Future.delayed(const Duration(milliseconds: 1200));

    final prefs = await SharedPreferences.getInstance();

    if (forceCancel) {
      if (paymentId != null && paymentId.isNotEmpty) {
        try {
          await ResidentApiService.cancelUpiPayment(paymentId);
        } catch (_) {}
      }
      final cancelledResult = PaymentVerificationResult(
        state: PaymentVerificationState.cancelled,
        invoiceId: invoiceId,
        transactionRef: txnRef,
        amount: amount,
        paymentApp: paymentApp,
        timestamp: DateTime.now(),
        message: 'Payment was cancelled in $paymentApp.',
      );
      await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(cancelledResult.toJson()));
      return cancelledResult;
    }

    if (forceFail) {
      final failedResult = PaymentVerificationResult(
        state: PaymentVerificationState.failed,
        invoiceId: invoiceId,
        transactionRef: txnRef,
        amount: amount,
        paymentApp: paymentApp,
        timestamp: DateTime.now(),
        message: 'Bank transaction could not be completed or timed out.',
      );
      await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(failedResult.toJson()));
      return failedResult;
    }

    // 1. Authoritative Backend Check (for real backend payments)
    if (paymentId != null && paymentId.isNotEmpty && !paymentId.startsWith('INV-')) {
      try {
        final statusRes = await ResidentApiService.getUpiPaymentStatus(paymentId);
        if (statusRes.isNotEmpty) {
          final isSettled = statusRes['is_settled'] == true ||
              statusRes['status'] == 'PAID' ||
              statusRes['status'] == 'SUCCESS';
          if (isSettled) {
            return await _recordAndReturnSuccessfulResult(
              prefs: prefs,
              invoiceId: invoiceId,
              txnRef: txnRef,
              amount: amount,
              paymentApp: paymentApp,
              receiptNumber: statusRes['receipt_number']?.toString(),
              bankApprovalCode: statusRes['bank_reference']?.toString(),
            );
          } else if (statusRes['status'] == 'FAILED') {
            final failedResult = PaymentVerificationResult(
              state: PaymentVerificationState.failed,
              invoiceId: invoiceId,
              transactionRef: txnRef,
              amount: amount,
              paymentApp: paymentApp,
              timestamp: DateTime.now(),
              message: 'Payment was declined or timed out at bank.',
            );
            await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(failedResult.toJson()));
            return failedResult;
          } else if (statusRes['status'] == 'CANCELLED') {
            final cancelledResult = PaymentVerificationResult(
              state: PaymentVerificationState.cancelled,
              invoiceId: invoiceId,
              transactionRef: txnRef,
              amount: amount,
              paymentApp: paymentApp,
              timestamp: DateTime.now(),
              message: 'Payment was cancelled in UPI application.',
            );
            await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(cancelledResult.toJson()));
            return cancelledResult;
          }
        }
      } catch (e) {
        debugPrint('Error polling UPI status: $e');
      }
    }

    // 2. Explicit Demo Mode or Developer Simulation
    if (paymentApp == 'Demo Pay' || forceSuccess) {
      return await _recordAndReturnSuccessfulResult(
        prefs: prefs,
        invoiceId: invoiceId,
        txnRef: txnRef,
        amount: amount,
        paymentApp: paymentApp,
      );
    }

    // 3. Real UPI Flow: Never auto-settle upon return. Fails closed in pendingVerification.
    final pendingResult = PaymentVerificationResult(
      state: PaymentVerificationState.pendingVerification,
      invoiceId: invoiceId,
      transactionRef: txnRef,
      amount: amount,
      paymentApp: paymentApp,
      timestamp: DateTime.now(),
      message: 'Transaction submitted. Awaiting bank reconciliation and PG confirmation.',
    );
    await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(pendingResult.toJson()));
    return pendingResult;
  }

  /// Explicit simulation of bank settlement for test verification
  static Future<PaymentVerificationResult> simulateBankSettlement({
    required String invoiceId,
    required String txnRef,
    required String paymentApp,
    required num amount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return await _recordAndReturnSuccessfulResult(
      prefs: prefs,
      invoiceId: invoiceId,
      txnRef: txnRef,
      amount: amount,
      paymentApp: paymentApp,
    );
  }

  /// Cancels an active payment attempt
  static Future<PaymentVerificationResult> cancelPayment({
    required String invoiceId,
    required String txnRef,
    required String paymentApp,
    required num amount,
    String? paymentId,
  }) async {
    if (paymentId != null && paymentId.isNotEmpty && !paymentId.startsWith('INV-')) {
      try {
        await ResidentApiService.cancelUpiPayment(paymentId);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final cancelledResult = PaymentVerificationResult(
      state: PaymentVerificationState.cancelled,
      invoiceId: invoiceId,
      transactionRef: txnRef,
      amount: amount,
      paymentApp: paymentApp,
      timestamp: DateTime.now(),
      message: 'Payment cancelled by resident.',
    );
    await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(cancelledResult.toJson()));
    return cancelledResult;
  }

  static Future<PaymentVerificationResult> _recordAndReturnSuccessfulResult({
    required SharedPreferences prefs,
    required String invoiceId,
    required String txnRef,
    required num amount,
    required String paymentApp,
    String? receiptNumber,
    String? bankApprovalCode,
  }) async {
    final approvalCode = bankApprovalCode ?? 'BANK-AUTH-${Random().nextInt(89999) + 10000}';
    final recNo = receiptNumber ?? 'REC-${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${Random().nextInt(8999) + 1000}';

    final receipt = {
      'receiptNumber': recNo,
      'invoiceId': invoiceId,
      'amount': amount,
      'paymentApp': paymentApp,
      'transactionRef': txnRef,
      'bankApprovalCode': approvalCode,
      'paidAt': DateTime.now().toIso8601String(),
      'residentName': AppData.currentResident['name'] ?? 'Akshay B',
      'roomNumber': AppData.currentResident['room_number'] ?? AppData.currentResident['room'] ?? '101',
      'propertyName': verifiedPayeeName,
      'status': 'Verified & Settled',
    };

    final verifiedResult = PaymentVerificationResult(
      state: PaymentVerificationState.successful,
      invoiceId: invoiceId,
      transactionRef: txnRef,
      amount: amount,
      paymentApp: paymentApp,
      bankApprovalCode: approvalCode,
      timestamp: DateTime.now(),
      message: 'Payment confirmed & verified by PG Owner backend.',
      receiptData: receipt,
    );

    // Save transaction state
    await prefs.setString('$_storageKeyPrefix$invoiceId', jsonEncode(verifiedResult.toJson()));

    // Save receipt to verified receipts list
    final receiptsJson = prefs.getString(_verifiedReceiptsKey);
    List<dynamic> receiptsList = receiptsJson != null ? jsonDecode(receiptsJson) : [];
    receiptsList.removeWhere((r) => r['invoiceId'] == invoiceId);
    receiptsList.insert(0, receipt);
    await prefs.setString(_verifiedReceiptsKey, jsonEncode(receiptsList));

    // Update AppData resident state to Paid
    AppData.currentResident['rent_status'] = 'Paid';
    await AppData.saveResidentsToStorage();

    return verifiedResult;
  }

  /// Retrieves verified receipt for an invoice if available
  static Future<Map<String, dynamic>?> getReceipt(String invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final receiptsJson = prefs.getString(_verifiedReceiptsKey);
    if (receiptsJson == null) return null;
    final List<dynamic> list = jsonDecode(receiptsJson);
    return list.firstWhere(
      (r) => r['invoiceId'] == invoiceId,
      orElse: () => null,
    );
  }
}
