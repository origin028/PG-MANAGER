import 'package:flutter/foundation.dart';
import '../network/api_client.dart';

class ResidentApiService {
  // ---------------------------------------------------------------------------
  // Dashboard & Notices
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getDashboard() async {
    final res = await ApiClient.get('/resident/dashboard');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> getNotices() async {
    final res = await ApiClient.get('/notices');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Weekly Food Menu
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getWeeklyFoodMenu() async {
    final res = await ApiClient.get('/resident/food-menu');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Invoices & Payments
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getInvoices({String? status}) async {
    final query = <String, dynamic>{
      if (status != null && status.isNotEmpty && status != 'ALL') 'status': status,
    };
    final res = await ApiClient.get('/resident/invoices', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> getInvoiceDetail(String invoiceId) async {
    final res = await ApiClient.get('/resident/invoices/$invoiceId');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> getPayments() async {
    final res = await ApiClient.get('/resident/payments');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Rent Payment Execution (UPI & Demo Pay)
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> payDemo({
    required String invoiceId,
    required double amount,
    String? idempotencyKey,
  }) async {
    final res = await ApiClient.post(
      '/payments/demo/pay',
      body: {
        'invoice_id': invoiceId,
        'amount': amount,
        'payment_mode': 'DEMO_ONLINE',
        if (idempotencyKey != null && idempotencyKey.isNotEmpty) 'idempotency_key': idempotencyKey,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Initiates direct UPI payment intent on backend (authoritative calculation)
  static Future<Map<String, dynamic>> initiateDirectUpiPayment({
    required String invoiceId,
    String? idempotencyKey,
  }) async {
    final res = await ApiClient.post(
      '/payments/upi/initiate',
      body: {
        'invoice_id': invoiceId,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty) 'idempotency_key': idempotencyKey,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Records return from UPI app (sets state to PENDING_VERIFICATION)
  static Future<Map<String, dynamic>> recordUpiReturn(String paymentId) async {
    final res = await ApiClient.post(
      '/payments/upi/$paymentId/return',
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Records resident cancellation of a pending UPI payment attempt
  static Future<Map<String, dynamic>> cancelUpiPayment(String paymentId) async {
    final res = await ApiClient.post(
      '/payments/upi/$paymentId/cancel',
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Queries authoritative payment status from backend
  static Future<Map<String, dynamic>> getUpiPaymentStatus(String paymentId) async {
    final res = await ApiClient.get(
      '/payments/upi/$paymentId/status',
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Sends client-side verification query (fails closed; never auto-settles)
  static Future<Map<String, dynamic>> verifyUpiPaymentAttempt(
    String paymentId, {
    Map<String, dynamic>? clientData,
  }) async {
    final res = await ApiClient.post(
      '/payments/upi/$paymentId/verify',
      body: clientData ?? {},
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> initiateUpiRequest({
    required String invoiceId,
    required double amount,
    String? vpa,
  }) async {
    final res = await ApiClient.post(
      '/payments/requests',
      body: {
        'invoice_id': invoiceId,
        'amount': amount,
        if (vpa != null && vpa.isNotEmpty) 'vpa': vpa,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getPaymentRequestStatus(String requestId) async {
    final res = await ApiClient.get('/payments/requests/$requestId');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Profile & Property
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getProfile() async {
    final res = await ApiClient.get('/resident/profile');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getPropertyDetails() async {
    final res = await ApiClient.get('/resident/property');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getPropertyContacts() async {
    final res = await ApiClient.get('/resident/property-contacts');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Complaints & Photo Upload
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getComplaints() async {
    final res = await ApiClient.get('/resident/complaints');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> createComplaint(Map<String, dynamic> payload) async {
    final res = await ApiClient.post('/resident/complaints', body: payload);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> uploadComplaintPhoto({
    required List<int> fileBytes,
    required String filename,
  }) async {
    final res = await ApiClient.uploadMultipart(
      path: '/resident/complaints/upload-photo',
      fieldName: 'photo',
      fileBytes: fileBytes,
      filename: filename,
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Resident App Settings
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getSettings() async {
    final res = await ApiClient.get('/resident/settings');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> payload) async {
    final res = await ApiClient.patch('/resident/settings', body: payload);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Receipts & PDF Download
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getReceipts() async {
    final res = await ApiClient.get('/receipts/my');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> getReceiptDetail(String receiptId) async {
    final res = await ApiClient.get('/receipts/$receiptId');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Uint8List> downloadReceiptPdf(String receiptId) async {
    return await ApiClient.getBytes('/receipts/$receiptId/pdf');
  }

  // ---------------------------------------------------------------------------
  // Notifications & Read Status
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getNotifications({bool unreadOnly = false}) async {
    final res = await ApiClient.get('/notifications', queryParameters: {'unread_only': unreadOnly});
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<int> getUnreadNotificationCount() async {
    final res = await ApiClient.get('/notifications/unread-count');
    if (res is Map && res.containsKey('unread_count')) {
      return (res['unread_count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  static Future<Map<String, dynamic>> updateProfile({String? fullName, String? avatarUrl, String? phone}) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    if (phone != null) body['phone'] = phone;
    final res = await ApiClient.patch('/users/me', body: body);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> markNotificationRead(String id) async {
    await ApiClient.patch('/notifications/$id/read');
  }

  static Future<void> markAllNotificationsRead() async {
    await ApiClient.post('/notifications/read-all');
  }
}
