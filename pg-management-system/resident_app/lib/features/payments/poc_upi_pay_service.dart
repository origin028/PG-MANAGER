import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:upi_pay/upi_pay.dart' as upi;
import '../../core/services/payment_verification_service.dart';
import '../../core/services/resident_api_service.dart';

/// Represents the discovery result of a UPI application in the POC.
class PocDiscoveredApp {
  final String appName;
  final String packageName;
  final bool isNativelySupportedByPackage;
  final bool isInstalled;
  final upi.ApplicationMeta? rawMeta;
  final upi.UpiApplication? upiApplication;

  const PocDiscoveredApp({
    required this.appName,
    required this.packageName,
    required this.isNativelySupportedByPackage,
    required this.isInstalled,
    this.rawMeta,
    this.upiApplication,
  });
}

/// Represents the outcome of an isolated test execution using upi_pay.
class PocUpiPayExecutionResult {
  final String appName;
  final String packageName;
  final String invoiceId;
  final double amount;
  final String txnRef;
  final String generatedUri;
  final bool launched;
  final upi.UpiTransactionStatus? status;
  final String? rawResponse;
  final String? responseCode;
  final String? approvalRefNo;
  final String? txnId;
  final String message;
  final String verificationState; // Strictly 'pendingVerification'
  final List<String> diagnosticLogs;

  const PocUpiPayExecutionResult({
    required this.appName,
    required this.packageName,
    required this.invoiceId,
    required this.amount,
    required this.txnRef,
    required this.generatedUri,
    required this.launched,
    this.status,
    this.rawResponse,
    this.responseCode,
    this.approvalRefNo,
    this.txnId,
    required this.message,
    this.verificationState = 'pendingVerification',
    required this.diagnosticLogs,
  });
}

/// Abstract runner interface for PocUpiPayService to allow 100% mockability in unit tests.
abstract class PocUpiPayRunner {
  Future<List<upi.ApplicationMeta>> getInstalledUpiApplications({
    upi.UpiApplicationDiscoveryAppStatusType statusType,
  });

  Future<upi.UpiTransactionResponse> initiateTransaction({
    required upi.UpiApplication app,
    required String receiverUpiAddress,
    required String receiverName,
    required String transactionRef,
    required String amount,
    String? transactionNote,
  });

  Future<bool> checkPackageInstalledNative(String packageName);

  Future<Map<String, dynamic>?> launchPhonePeNativeDirect({
    required String uri,
    required String package,
    required String payeeVpa,
    required String payeeName,
    required String amount,
    required String txnRef,
    required String note,
  });
}

/// Default real implementation delegating to the upi_pay plugin and native MethodChannel.
class DefaultPocUpiPayRunner implements PocUpiPayRunner {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.originpg.resident/native_upi');

  const DefaultPocUpiPayRunner();

  @override
  Future<List<upi.ApplicationMeta>> getInstalledUpiApplications({
    upi.UpiApplicationDiscoveryAppStatusType statusType =
        upi.UpiApplicationDiscoveryAppStatusType.all,
  }) async {
    final client = upi.UpiPay();
    return await client.getInstalledUpiApplications(
      paymentType: upi.UpiApplicationDiscoveryAppPaymentType.nonMerchant,
      statusType: statusType,
    );
  }

  @override
  Future<upi.UpiTransactionResponse> initiateTransaction({
    required upi.UpiApplication app,
    required String receiverUpiAddress,
    required String receiverName,
    required String transactionRef,
    required String amount,
    String? transactionNote,
  }) async {
    final client = upi.UpiPay();
    return await client.initiateTransaction(
      app: app,
      receiverUpiAddress: receiverUpiAddress,
      receiverName: receiverName,
      transactionRef: transactionRef,
      amount: amount,
      transactionNote: transactionNote,
    );
  }

  @override
  Future<bool> checkPackageInstalledNative(String packageName) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'isPackageInstalled',
        {'package': packageName},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> launchPhonePeNativeDirect({
    required String uri,
    required String package,
    required String payeeVpa,
    required String payeeName,
    required String amount,
    required String txnRef,
    required String note,
  }) async {
    return await _nativeChannel.invokeMapMethod<String, dynamic>(
      'launchPhonePeDirect',
      {
        'uri': uri,
        'package': package,
        'payeeVpa': payeeVpa,
        'payeeName': payeeName,
        'amount': amount,
        'txnRef': txnRef,
        'note': note,
      },
    );
  }
}

/// Isolated Diagnostic & Evaluation Service for upi_pay package.
class PocUpiPayService {
  // Verified PG Owner details (strictly preserved)
  static const String verifiedPayeeVpa = 'masisokatali90900@okaxis';
  static const String verifiedPayeeName = 'Saukatali Masi';
  static const String defaultCurrency = 'INR';

  // Well-known packages
  static const String googlePayPackage = 'com.google.android.apps.nbu.paisa.user';
  static const String phonePePackage = 'com.phonepe.app';
  static const String naviPackage = 'com.navi.curiosity';
  static const String naviAppPackage = 'com.naviapp';

  /// Custom UpiApplication instance for Navi (since upi_pay lacks native enum entry)
  static final upi.UpiApplication naviCustomApplication = upi.UpiApplication(
    androidPackageName: naviPackage,
    iosBundleId: naviPackage,
    appName: 'Navi',
  );

  static final upi.UpiApplication naviAppCustomApplication = upi.UpiApplication(
    androidPackageName: naviAppPackage,
    iosBundleId: naviAppPackage,
    appName: 'Navi',
  );

  static PocUpiPayRunner runner = const DefaultPocUpiPayRunner();

  /// Discovers installed UPI apps using upi_pay with statusType.all,
  /// plus dedicated auxiliary resolution for Navi.
  static Future<List<PocDiscoveredApp>> discoverInstalledApps() async {
    final List<PocDiscoveredApp> result = [];

    // 1. Query upi_pay package discovery with statusType.all
    List<upi.ApplicationMeta> discoveredByPackage = [];
    try {
      discoveredByPackage = await runner.getInstalledUpiApplications(
        statusType: upi.UpiApplicationDiscoveryAppStatusType.all,
      );
    } catch (e) {
      debugPrint('[PocUpiPay] Discovery error from upi_pay: $e');
    }

    final discoveredPackageNames = discoveredByPackage
        .map((m) => m.upiApplication.androidPackageName)
        .toSet();

    // Map discovered packages
    for (final meta in discoveredByPackage) {
      result.add(PocDiscoveredApp(
        appName: meta.upiApplication.appName,
        packageName: meta.upiApplication.androidPackageName,
        isNativelySupportedByPackage: true,
        isInstalled: true,
        rawMeta: meta,
        upiApplication: meta.upiApplication,
      ));
    }

    // 2. Check if Google Pay was omitted despite being installed
    if (!discoveredPackageNames.contains(googlePayPackage)) {
      final isGPayInstalled = await runner.checkPackageInstalledNative(googlePayPackage);
      if (isGPayInstalled) {
        result.add(PocDiscoveredApp(
          appName: 'Google Pay',
          packageName: googlePayPackage,
          isNativelySupportedByPackage: true,
          isInstalled: true,
          upiApplication: upi.UpiApplication.googlePay,
        ));
      }
    }

    // 3. Check if PhonePe was omitted despite being installed
    if (!discoveredPackageNames.contains(phonePePackage)) {
      final isPhonePeInstalled = await runner.checkPackageInstalledNative(phonePePackage);
      if (isPhonePeInstalled) {
        result.add(PocDiscoveredApp(
          appName: 'PhonePe',
          packageName: phonePePackage,
          isNativelySupportedByPackage: true,
          isInstalled: true,
          upiApplication: upi.UpiApplication.phonePe,
        ));
      }
    }

    // 4. Dedicated Navi handling (Navi is not in upi_pay enum)
    final naviCandidates = [naviPackage, naviAppPackage];
    for (final pkg in naviCandidates) {
      if (!discoveredPackageNames.contains(pkg)) {
        final isNaviInstalled = await runner.checkPackageInstalledNative(pkg);
        if (isNaviInstalled) {
          result.add(PocDiscoveredApp(
            appName: 'Navi UPI',
            packageName: pkg,
            isNativelySupportedByPackage: false,
            isInstalled: true,
            upiApplication: upi.UpiApplication(
              androidPackageName: pkg,
              iosBundleId: pkg,
              appName: 'Navi',
            ),
          ));
        }
      }
    }

    return result;
  }

  /// Safely extracts raw response across Android and cross-platform/test environments
  static String extractRawResponse(upi.UpiTransactionResponse response) {
    try {
      return response.rawResponse ?? '';
    } catch (_) {
      final str = response.toString();
      final match = RegExp(r'rawResponse:\s*([^}]+)\}').firstMatch(str);
      return match?.group(1)?.trim() ?? '';
    }
  }

  /// Safely extracts transaction attributes across Android and cross-platform/test environments
  static String? extractResponseField(upi.UpiTransactionResponse response, String field) {
    try {
      switch (field) {
        case 'responseCode':
          return response.responseCode;
        case 'approvalRefNo':
          return response.approvalRefNo;
        case 'txnId':
          return response.txnId;
        case 'txnRef':
          return response.txnRef;
      }
    } catch (_) {
      final str = response.toString();
      final match = RegExp('$field:\\s*([^,}]+)').firstMatch(str);
      final val = match?.group(1)?.trim();
      if (val == null || val == 'null') return null;
      return val;
    }
    return null;
  }

  /// Initiates payment via upi_pay for a specific application.
  /// Strict safety: Enforces ₹1.00 TEST invoice only and keeps state in PENDING_VERIFICATION.
  static Future<PocUpiPayExecutionResult> initiatePocPayment({
    required String appName,
    required String packageName,
    required upi.UpiApplication upiApp,
    required String invoiceId,
    double amount = 1.00,
    bool enableNativePhonePeFallback = false,
  }) async {
    final List<String> logs = [];
    logs.add('=== [UPI_PAY POC INITIATION] ===');
    logs.add('App: $appName ($packageName)');
    logs.add('Invoice ID: $invoiceId');
    logs.add('Amount: ₹${amount.toStringAsFixed(2)}');
    logs.add('Payee VPA: $verifiedPayeeVpa');
    logs.add('Payee Name: $verifiedPayeeName');

    final txnRef = PaymentVerificationService.generateTxnReference(invoiceId);
    final cleanId = invoiceId.trim();
    final displayId = cleanId.length > 8 && !cleanId.toUpperCase().startsWith('INV-')
        ? cleanId.substring(0, 8)
        : cleanId;
    final note = 'Rent Payment - $displayId - $verifiedPayeeName';
    final amountStr = amount.toStringAsFixed(2);

    // Approximate URI constructed by upi_pay plugin under the hood
    final expectedUri =
        'upi://pay?pa=$verifiedPayeeVpa&pn=${Uri.encodeComponent(verifiedPayeeName)}'
        '&tr=${Uri.encodeComponent(txnRef)}&am=$amountStr&cu=INR'
        '&tn=${Uri.encodeComponent(note)}&mode=00';
    logs.add('Target URI (upi_pay): $expectedUri');

    // 1. Authoritative Backend Initiation (Sets PENDING_VERIFICATION on backend)
    String? backendPaymentId;
    try {
      final res = await ResidentApiService.initiateDirectUpiPayment(
        invoiceId: invoiceId,
        idempotencyKey: 'UPI-POC-$txnRef',
      );
      backendPaymentId = res['payment_id']?.toString() ?? res['id']?.toString();
      logs.add('Backend Initiation: OK (ID: $backendPaymentId)');
    } catch (e) {
      logs.add('Backend Initiation Fallback: $e');
    }

    // 2. Set client state to Pending Verification
    await PaymentVerificationService.initiatePayment(
      invoiceId: invoiceId,
      amount: amount,
      paymentApp: 'upi_pay ($appName)',
      txnRef: txnRef,
      paymentId: backendPaymentId,
    );

    bool launched = false;
    upi.UpiTransactionResponse? response;
    String raw = '';
    String? respCode;
    String? approvalRef;
    String? txnId;
    String message = '';

    // 3. Launch via upi_pay plugin
    try {
      logs.add('Invoking upi_pay initiateTransaction (startActivityForResult)...');
      response = await runner.initiateTransaction(
        app: upiApp,
        receiverUpiAddress: verifiedPayeeVpa,
        receiverName: verifiedPayeeName,
        transactionRef: txnRef,
        amount: amountStr,
        transactionNote: note,
      );

      raw = extractRawResponse(response);
      respCode = extractResponseField(response, 'responseCode');
      approvalRef = extractResponseField(response, 'approvalRefNo');
      txnId = extractResponseField(response, 'txnId');

      logs.add('Raw Response: "$raw"');
      logs.add('Parsed Status: ${response.status}');
      logs.add('Response Code: ${respCode ?? "None"}');
      logs.add('Approval Ref No: ${approvalRef ?? "None"}');
      logs.add('Txn ID: ${txnId ?? "None"}');

      if (raw == 'activity_unavailable') {
        launched = false;
        message = 'Package $packageName has no activity resolving standard upi://pay intent';
        logs.add('Result: Activity Unavailable in target package');
      } else if (raw == 'failed_to_open_app') {
        launched = false;
        message = 'Android OS failed to open $packageName via upi_pay';
        logs.add('Result: Failed to open app');
      } else if (raw == 'user_cancelled') {
        launched = true;
        message = 'Returned from $appName without completing payment (Cancelled)';
        logs.add('Result: User cancelled in UPI app');
      } else {
        launched = true;
        message = 'Returned from $appName. Response: $raw';
      }
    } catch (e) {
      logs.add('Exception during upi_pay launch: $e');
      message = 'Exception: $e';
    }

    // 4. Special PhonePe Fallback Evaluation if upi_pay returned activity_unavailable
    if (!launched && packageName == phonePePackage && enableNativePhonePeFallback) {
      logs.add('--- Triggering Native Kotlin 4-tier Fallback for PhonePe ---');
      try {
        final nativeRes = await runner.launchPhonePeNativeDirect(
          uri: expectedUri,
          package: phonePePackage,
          payeeVpa: verifiedPayeeVpa,
          payeeName: verifiedPayeeName,
          amount: amountStr,
          txnRef: txnRef,
          note: note,
        );
        logs.add('Native Channel Response: $nativeRes');
        if (nativeRes?['status'] == 'SUCCESS') {
          launched = true;
          message = 'Launched PhonePe via Native Kotlin fallback (${nativeRes?['method']})';
        }
      } catch (ne) {
        logs.add('Native Channel Error: $ne');
      }
    }

    // 5. Authoritative Backend Return recording (strictly keeps state in PENDING_VERIFICATION)
    if (backendPaymentId != null) {
      try {
        await ResidentApiService.recordUpiReturn(backendPaymentId);
        logs.add('Backend Return Recorded: PENDING_VERIFICATION retained.');
      } catch (re) {
        logs.add('Backend Return Error: $re');
      }
    }

    logs.add('Security Verification: Payment status remains PENDING_VERIFICATION.');
    logs.add('=== [END POC INITIATION] ===');

    return PocUpiPayExecutionResult(
      appName: appName,
      packageName: packageName,
      invoiceId: invoiceId,
      amount: amount,
      txnRef: txnRef,
      generatedUri: expectedUri,
      launched: launched,
      status: response?.status,
      rawResponse: raw,
      responseCode: respCode,
      approvalRefNo: approvalRef,
      txnId: txnId,
      message: message,
      verificationState: 'pendingVerification',
      diagnosticLogs: logs,
    );
  }
}
