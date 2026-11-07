import 'dart:typed_data';
import '../network/api_client.dart';

class AdminApiService {
  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getProperties() async {
    final res = await ApiClient.get('/properties');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> createProperty(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/properties', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateProperty(String propertyId, Map<String, dynamic> data) async {
    final res = await ApiClient.put('/properties/$propertyId', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> deleteProperty(String propertyId) async {
    await ApiClient.delete('/properties/$propertyId');
  }

  // ---------------------------------------------------------------------------
  // Rooms & Beds
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getFloorRooms(String propertyId) async {
    final res = await ApiClient.get(
      '/rooms/floor-wise',
      queryParameters: {'property_id': propertyId},
    );
    if (res is Map<String, dynamic> && res['floors'] is List) {
      return (res['floors'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> createRoom(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/rooms', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> createBed(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/beds', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> deleteRoom(String roomId) async {
    await ApiClient.delete('/rooms/$roomId');
  }

  static Future<void> deleteBed(String bedId) async {
    await ApiClient.delete('/beds/$bedId');
  }

  // ---------------------------------------------------------------------------
  // Residents & KYC
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getResidents({
    String? propertyId,
    String? status,
    String? kycStatus,
    String? search,
  }) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (status != null && status.isNotEmpty && status != 'ALL') 'status': status,
      if (kycStatus != null && kycStatus.isNotEmpty && kycStatus != 'ALL') 'kyc_status': kycStatus,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res = await ApiClient.get('/residents', queryParameters: query);
    if (res is Map && res['items'] is List) {
      return (res['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> getResidentDetail(String residentId) async {
    final res = await ApiClient.get('/residents/$residentId');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> onboardResident(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/residents', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> verifyResidentKYC(String residentId) async {
    final res = await ApiClient.post('/residents/$residentId/verify-kyc');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> rejectResidentKYC(String residentId, {String? notes}) async {
    final res = await ApiClient.post(
      '/residents/$residentId/reject-kyc',
      body: {'notes': notes ?? 'Documents invalid or incomplete'},
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateResident(String residentId, Map<String, dynamic> data) async {
    final res = await ApiClient.patch('/residents/$residentId', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> transferResident({
    required String residentId,
    required String newRoomId,
    String? newBedId,
  }) async {
    final body = <String, dynamic>{
      'room_id': newRoomId,
      if (newBedId != null && newBedId.isNotEmpty) 'bed_id': newBedId,
    };
    return await updateResident(residentId, body);
  }

  static Future<Uint8List?> getKycDocumentBytes(String residentId, String docType) async {
    try {
      final res = await ApiClient.getRaw('/residents/$residentId/kyc-document/$docType');
      if (res.statusCode == 200) {
        return res.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingResidentApprovals({
    String? propertyId,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (search != null && search.isNotEmpty) 'search': search,
      'page': page,
      'page_size': pageSize,
    };
    final res = await ApiClient.get('/residents/pending-approvals', queryParameters: query);
    if (res is Map && res['items'] is List) {
      return (res['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> approveResident(
    String residentId, {
    String? roomId,
    String? bedId,
    double? monthlyRent,
    double? securityDeposit,
    String? checkInDate,
  }) async {
    final body = <String, dynamic>{};
    if (roomId != null) body['room_id'] = roomId;
    if (bedId != null) body['bed_id'] = bedId;
    if (monthlyRent != null) body['monthly_rent'] = monthlyRent;
    if (securityDeposit != null) body['security_deposit'] = securityDeposit;
    if (checkInDate != null) body['check_in_date'] = checkInDate;

    final res = await ApiClient.post('/residents/$residentId/approve', body: body);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> rejectResident(
    String residentId, {
    required String reason,
  }) async {
    final res = await ApiClient.post(
      '/residents/$residentId/reject',
      body: {'reason': reason},
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> checkoutResident(
    String residentId, {
    double damageCharges = 0.0,
    String? damageNotes,
    bool forceCheckout = false,
  }) async {
    final res = await ApiClient.post(
      '/residents/$residentId/checkout',
      body: {
        'damage_charges': damageCharges,
        'damage_notes': damageNotes,
        'force_checkout': forceCheckout,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Invoices & Rent Collection
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> createInvoice({
    required String propertyId,
    required String residentId,
    required double amount,
    required String billingMonth,
    required String dueDate,
    String invoiceType = 'TEST',
    String? notes,
  }) async {
    final res = await ApiClient.post(
      '/invoices',
      body: {
        'property_id': propertyId,
        'resident_id': residentId,
        'amount': amount,
        'billing_month': billingMonth,
        'due_date': dueDate,
        'invoice_type': invoiceType,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> getInvoices({
    String? propertyId,
    String? residentId,
    String? status,
  }) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (residentId != null && residentId.isNotEmpty) 'resident_id': residentId,
      if (status != null && status.isNotEmpty && status != 'ALL') 'status': status,
    };
    final res = await ApiClient.get('/invoices', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> collectPayment({
    required String invoiceId,
    required double amount,
    required String paymentMode,
    String? referenceNumber,
    String? notes,
  }) async {
    final res = await ApiClient.post(
      '/payments/collect',
      body: {
        'invoice_id': invoiceId,
        'amount': amount,
        'payment_mode': paymentMode,
        if (referenceNumber != null && referenceNumber.isNotEmpty) 'reference_number': referenceNumber,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> getPayments({String? propertyId}) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
    };
    final res = await ApiClient.get('/payments', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getExpenses({
    String? propertyId,
    String? category,
  }) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (category != null && category.isNotEmpty && category != 'ALL') 'category': category,
    };
    final res = await ApiClient.get('/expenses', queryParameters: query);
    if (res is Map && res['expenses'] is List) {
      return (res['expenses'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> createExpense(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/expenses', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> deleteExpense(String expenseId) async {
    await ApiClient.delete('/expenses/$expenseId');
  }

  // ---------------------------------------------------------------------------
  // Staff
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getStaff({String? propertyId}) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
    };
    final res = await ApiClient.get('/staff', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> createStaff(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/staff', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> deleteStaff(String staffId) async {
    await ApiClient.delete('/staff/$staffId');
  }

  static Future<Map<String, dynamic>> updateStaff(String staffId, Map<String, dynamic> data) async {
    final res = await ApiClient.patch('/staff/$staffId', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Weekly Food Menu
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getWeeklyFoodMenu(String propertyId) async {
    final res = await ApiClient.get(
      '/food-menus',
      queryParameters: {'property_id': propertyId},
    );
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> saveFoodMenuItem(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/food-menus', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Complaints & Maintenance
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getComplaints({
    String? propertyId,
    String? status,
    String? category,
  }) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (status != null && status.isNotEmpty && status != 'ALL') 'status': status,
      if (category != null && category.isNotEmpty && category != 'ALL') 'category': category,
    };
    final res = await ApiClient.get('/complaints', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> assignComplaint(String complaintId, String staffId) async {
    final res = await ApiClient.post(
      '/complaints/$complaintId/assign',
      body: {
        'assigned_staff_id': staffId,
        'staff_id': staffId,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> resolveComplaint(String complaintId, {String? notes}) async {
    final res = await ApiClient.post(
      '/complaints/$complaintId/resolve',
      body: {'resolution_notes': notes ?? 'Issue has been inspected and resolved.'},
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateComplaint(String complaintId, Map<String, dynamic> data) async {
    final res = await ApiClient.patch('/complaints/$complaintId', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Leads & CRM
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getLeads({
    String? propertyId,
    String? status,
  }) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (status != null && status.isNotEmpty && status != 'ALL') 'status': status,
    };
    final res = await ApiClient.get('/leads', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> createLead(Map<String, dynamic> data) async {
    final res = await ApiClient.post('/leads', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateLead(String leadId, Map<String, dynamic> data) async {
    final res = await ApiClient.patch('/leads/$leadId', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> deleteLead(String leadId) async {
    await ApiClient.delete('/leads/$leadId');
  }

  static Future<Map<String, dynamic>> convertLead(String leadId, [Map<String, dynamic>? data]) async {
    final res = await ApiClient.post('/leads/$leadId/convert', body: data ?? {});
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Notices
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getNotices({String? propertyId}) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
    };
    final res = await ApiClient.get('/notices', queryParameters: query);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> broadcastNotice({
    required String propertyId,
    required String title,
    required String message,
    String priority = 'NORMAL',
  }) async {
    final res = await ApiClient.post(
      '/notices',
      body: {
        'property_id': propertyId,
        'title': title,
        'message': message,
        'priority': priority,
      },
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<void> deleteNotice(String noticeId) async {
    await ApiClient.delete('/notices/$noticeId');
  }

  // ---------------------------------------------------------------------------
  // Reports & Analytics
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getDashboardMetrics({String? propertyId}) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
    };
    final res = await ApiClient.get('/reports/dashboard', queryParameters: query);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getFinancialReport({String? propertyId}) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
    };
    final res = await ApiClient.get('/reports/financial', queryParameters: query);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getOccupancyReport(String propertyId) async {
    final res = await ApiClient.get('/reports/occupancy', queryParameters: {'property_id': propertyId});
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Uint8List> exportPaymentsReportCsv({String? propertyId, String? paymentMode, String? dateFrom, String? dateTo}) async {
    final query = <String, dynamic>{
      if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
      if (paymentMode != null && paymentMode.isNotEmpty) 'payment_mode': paymentMode,
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
    };
    return await ApiClient.getBytes('/reports/payments/export', queryParameters: query);
  }

  static Future<Uint8List> exportOccupancyReportCsv(String propertyId) async {
    return await ApiClient.getBytes('/reports/occupancy/export', queryParameters: {'property_id': propertyId});
  }

  // ---------------------------------------------------------------------------
  // Settings & Subscription
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getCompanySettings() async {
    final res = await ApiClient.get('/settings/company');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateCompanySettings(Map<String, dynamic> data) async {
    final res = await ApiClient.patch('/settings/company', body: data);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getSubscriptionQuota() async {
    final res = await ApiClient.get('/settings/subscription');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final res = await ApiClient.get('/notifications', queryParameters: {'unread_only': false});
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<void> markNotificationRead(String id) async {
    await ApiClient.patch('/notifications/$id/read');
  }

  static Future<void> markAllNotificationsRead() async {
    await ApiClient.post('/notifications/read-all');
  }

  // ---------------------------------------------------------------------------
  // Organization Bed Capacity (Fixed 240 Beds)
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getBedCapacity() async {
    final res = await ApiClient.get('/company/bed-capacity');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // Digital Payment Receipts & PDF Download
  // ---------------------------------------------------------------------------
  static Future<Uint8List> downloadReceiptPdf(String receiptId) async {
    return await ApiClient.getBytes('/receipts/$receiptId/pdf');
  }
}
