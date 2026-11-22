import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Predefined and dynamically discovered UPI applications on Android.
class UpiApp {
  final String name;
  final String packageName;
  final Uint8List? icon;

  const UpiApp({required this.name, required this.packageName, this.icon});

  static const UpiApp googlePay = UpiApp(
    name: 'Google Pay',
    packageName: 'com.google.android.apps.nbu.paisa.user',
  );

  static const UpiApp phonePe = UpiApp(
    name: 'PhonePe',
    packageName: 'com.phonepe.app',
  );

  static const UpiApp paytm = UpiApp(
    name: 'Paytm',
    packageName: 'net.one97.paytm',
  );

  static const UpiApp bhim = UpiApp(
    name: 'BHIM',
    packageName: 'in.org.npci.upiapp',
  );

  static const UpiApp amazonPay = UpiApp(
    name: 'Amazon Pay',
    packageName: 'in.amazon.mShop.android.shopping',
  );

  static const UpiApp cred = UpiApp(
    name: 'CRED',
    packageName: 'com.dreamplug.androidapp',
  );

  static const UpiApp navi = UpiApp(
    name: 'Navi',
    packageName: 'com.navi.curiosity',
  );

  factory UpiApp.fromMap(Map<dynamic, dynamic> map) {
    return UpiApp(
      name: (map['name'] as String?)?.trim() ?? '',
      packageName: (map['packageName'] as String?)?.trim() ?? '',
      icon: map['icon'] != null
          ? Uint8List.fromList(List<int>.from(map['icon'] as List))
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpiApp &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName;

  @override
  int get hashCode => packageName.hashCode;
}

/// Standard UPI payment statuses returned by UPI intent callbacks.
class UpiPaymentStatus {
  static const String success = 'success';
  static const String submitted = 'submitted';
  static const String failure = 'failure';
  static const String other = 'other';
}

/// Response returned by the UPI application upon completion of Intent.
class UpiResponse {
  String? transactionId;
  String? responseCode;
  String? approvalRefNo;
  String? status;
  String? transactionRefId;
  String? rawResponse;

  UpiResponse(String responseString) {
    rawResponse = responseString;
    final parts = responseString.split('&');
    for (final part in parts) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        final key = part.substring(0, idx).trim().toLowerCase();
        final value = part.substring(idx + 1).trim();
        final cleanVal = _cleanValue(value);

        if (key == 'txnid') {
          transactionId = cleanVal;
        } else if (key == 'responsecode') {
          responseCode = cleanVal;
        } else if (key == 'approvalrefno') {
          approvalRefNo = cleanVal;
        } else if (key == 'status') {
          final lower = cleanVal?.toLowerCase() ?? '';
          if (lower.contains('success')) {
            status = UpiPaymentStatus.success;
          } else if (lower.contains('fail')) {
            status = UpiPaymentStatus.failure;
          } else if (lower.contains('submit') || lower.contains('pending')) {
            status = UpiPaymentStatus.submitted;
          } else {
            status = UpiPaymentStatus.other;
          }
        } else if (key == 'txnref') {
          transactionRefId = cleanVal;
        }
      }
    }
  }

  static String? _cleanValue(String? s) {
    if (s == null || s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'undefined' || lower == '-') return null;
    return Uri.decodeComponent(s);
  }
}

/// High-reliability Direct UPI Intent Service using native Android MethodChannel.
/// Implements the exact parameter specification (`mode=04`, clean RFC 3986 encoding,
/// alphanumeric `tr`, no unverified `mc`) proven to work in `UPI-Plugin-Flutter`.
class UpiIndiaService {
  static const MethodChannel _channel = MethodChannel('com.az.upi_india');

  /// Queries all installed apps on device that can handle UPI Intents.
  static Future<List<UpiApp>> getAllUpiApps() async {
    try {
      final list = await _channel.invokeListMethod<Map>('getAllUpiApps');
      if (list != null) {
        return list.map((e) => UpiApp.fromMap(e)).toList();
      }
    } catch (e) {
      debugPrint('[UpiIndiaService] Error fetching UPI apps: $e');
    }
    return [];
  }

  /// Starts a direct UPI payment transaction for the target app.
  static Future<UpiResponse> startTransaction({
    required UpiApp app,
    required String receiverUpiId,
    required String receiverName,
    required String transactionRefId,
    String? transactionNote,
    required double amount,
    String currency = 'INR',
    String? merchantId,
  }) async {
    final cleanPn = receiverName.replaceAll("'", '').trim();
    final cleanTr = transactionRefId
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .trim();
    final cleanNote = (transactionNote ?? 'Rent Payment')
        .replaceAll('+', ' ')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final response = await _channel.invokeMethod<String>('startTransaction', {
      'app': app.packageName,
      'receiverUpiId': receiverUpiId.trim(),
      'receiverName': cleanPn,
      'transactionRefId': cleanTr.length > 35
          ? cleanTr.substring(0, 35)
          : cleanTr,
      'transactionNote': cleanNote.length > 50
          ? cleanNote.substring(0, 50)
          : cleanNote,
      'amount': amount.toStringAsFixed(2),
      'currency': currency,
      if (merchantId != null && merchantId.trim().isNotEmpty)
        'merchantId': merchantId.trim(),
    });

    return UpiResponse(response ?? '');
  }
}
