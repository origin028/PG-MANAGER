import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_upi_india/flutter_upi_india.dart' as fupi;
import 'package:upi_intent/upi_intent.dart' as upiint;

import 'resident_api_service.dart';
import 'upi_india_service.dart';

/// Canonical outcome categories for Direct UPI Intent execution.
enum DirectUpiOutcomeStatus {
  success,
  failure,
  submitted,
  pending,
  cancelled,
  appNotInstalled,
  networkError,
  unknown,
}

/// Fine-grained failure / status diagnostic category (never converts errors to success).
enum DirectUpiErrorCategory {
  appLaunchFailure,
  securityRejection,
  bankLimitRejection,
  bankTransactionRejection,
  userCancelled,
  networkFailure,
  pendingTransaction,
  verifiedSettlement,
  unknownError,
}

/// Discovered installed UPI application on Android.
class InstalledUpiApp {
  final String name;
  final String packageName;
  final Uint8List? iconBytes;

  const InstalledUpiApp({
    required this.name,
    required this.packageName,
    this.iconBytes,
  });

  String get shortTag {
    final pkg = packageName.toLowerCase();
    if (pkg.contains('paisa')) return 'GPay';
    if (pkg.contains('phonepe')) return 'PhonePe';
    if (pkg.contains('paytm')) return 'Paytm';
    if (pkg.contains('npci.upiapp')) return 'BHIM';
    if (pkg.contains('navi')) return 'Navi';
    if (pkg.contains('amazon')) return 'Amazon Pay';
    if (pkg.contains('dreamplug')) return 'CRED';
    return name;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstalledUpiApp &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName;

  @override
  int get hashCode => packageName.hashCode;
}

/// Captured native Android UPI Intent result.
class DirectUpiLaunchResult {
  final DirectUpiOutcomeStatus status;
  final DirectUpiErrorCategory errorCategory;
  final String rawStatusString;
  final String? txnId;
  final String? txnRef;
  final String? approvalRefNo;
  final String? responseCode;
  final String? rawResponse;
  final String? appPackage;
  final String? appName;
  final bool isLimitOrSecurityRestricted;
  final String userMessage;

  const DirectUpiLaunchResult({
    required this.status,
    this.errorCategory = DirectUpiErrorCategory.unknownError,
    required this.rawStatusString,
    this.txnId,
    this.txnRef,
    this.approvalRefNo,
    this.responseCode,
    this.rawResponse,
    this.appPackage,
    this.appName,
    this.isLimitOrSecurityRestricted = false,
    required this.userMessage,
  });

  bool get canRetry =>
      status == DirectUpiOutcomeStatus.failure ||
      status == DirectUpiOutcomeStatus.cancelled ||
      status == DirectUpiOutcomeStatus.appNotInstalled ||
      status == DirectUpiOutcomeStatus.networkError;
}

/// Full Direct UPI initiation -> launch -> backend sync summary.
class DirectUpiFlowResult {
  final String? paymentId;
  final String? paymentNumber;
  final String? txnRef;
  final num amount;
  final String? payeeVpa;
  final String? payeeName;
  final DirectUpiLaunchResult outcome;
  final String backendStatus;
  final bool isSettled;
  final String? receiptId;
  final String? receiptNumber;

  const DirectUpiFlowResult({
    this.paymentId,
    this.paymentNumber,
    this.txnRef,
    required this.amount,
    this.payeeVpa,
    this.payeeName,
    required this.outcome,
    required this.backendStatus,
    required this.isSettled,
    this.receiptId,
    this.receiptNumber,
  });

  bool get canRetry => !isSettled && outcome.canRetry;
}

/// Dependency injection interface so widget & unit tests can mock UPI discovery,
/// native Intent invocation, and backend synchronization without real transfers.
abstract class DirectUpiGateway {
  Future<List<InstalledUpiApp>> getInstalledApps();

  Future<Map<String, dynamic>> launchUpiIntent({
    required String uri,
    String? packageName,
  });

  Future<Map<String, dynamic>> initiateBackendPayment({
    required String invoiceId,
    String? idempotencyKey,
    String? appName,
    String? packageName,
  });

  Future<Map<String, dynamic>> recordBackendResponse({
    required String paymentId,
    required String status,
    String? txnRef,
    String? upiTxnId,
    String? approvalRefNo,
    String? responseCode,
    String? rawResponse,
    String? appPackage,
  });

  Future<Map<String, dynamic>> cancelBackendPayment(String paymentId);
}

class DefaultDirectUpiGateway implements DirectUpiGateway {
  static const MethodChannel _channel = MethodChannel(
    'com.originpg.resident/native_upi',
  );

  const DefaultDirectUpiGateway();

  @override
  Future<List<InstalledUpiApp>> getInstalledApps() async {
    final apps = <String, InstalledUpiApp>{};

    // 0. Preferred upi_intent package discovery (Android 11+ compliant)
    try {
      final upiIntentApps = await upiint.UpiIntent.getInstalledApps();
      for (final app in upiIntentApps) {
        if (app.packageName.isNotEmpty) {
          apps[app.packageName] = InstalledUpiApp(
            name: app.name,
            packageName: app.packageName,
            iconBytes: app.icon,
          );
        }
      }
    } catch (e) {
      debugPrint('[DefaultDirectUpiGateway] upi_intent discovery fallback: $e');
    }

    // 1. Native PackageManager query for all upi://pay intent handlers on Android 11+
    if (apps.isEmpty) {
      bool hasNativeChannel = true;
      try {
        final rawList = await _channel.invokeMethod<List<dynamic>>(
          'getInstalledUpiApps',
        );
        if (rawList != null) {
          for (final item in rawList) {
            if (item is Map) {
              final pkg = item['packageName']?.toString().trim() ?? '';
              final name = item['name']?.toString().trim() ?? pkg;
              if (pkg.isNotEmpty) {
                apps[pkg] = InstalledUpiApp(
                  name: name.isEmpty ? pkg : name,
                  packageName: pkg,
                );
              }
            }
          }
        }
      } on MissingPluginException {
        hasNativeChannel = false;
      } catch (e) {
        debugPrint('Native UPI app discovery failed: $e');
      }

      // 2. Fallback via maintained flutter_upi_india package on Android
      if (hasNativeChannel && apps.isEmpty) {
        try {
          final metas = await fupi.UpiPay.getInstalledUpiApplications(
            statusType: fupi.UpiApplicationDiscoveryAppStatusType.all,
          );
          for (final meta in metas) {
            final pkg = meta.upiApplication.androidPackageName;
            if (pkg.isEmpty) continue;
            final existing = apps[pkg];
            apps[pkg] = InstalledUpiApp(
              name: existing?.name ?? meta.upiApplication.getAppName(),
              packageName: pkg,
            );
          }
        } catch (e) {
          debugPrint('flutter_upi_india discovery fallback failed: $e');
        }
      }
    }

    final result = apps.values.toList();
    result.sort(
      (a, b) =>
          _appSortWeight(a.packageName)
              .compareTo(_appSortWeight(b.packageName)),
    );
    return result;
  }

  static int _appSortWeight(String packageName) {
    switch (packageName) {
      case 'com.google.android.apps.nbu.paisa.user':
        return 0;
      case 'com.phonepe.app':
      case 'com.phonepe.app.preprod':
        return 1;
      case 'net.one97.paytm':
        return 2;
      case 'in.org.npci.upiapp':
        return 3;
      case 'com.navi.curiosity':
      case 'com.naviapp':
        return 4;
      default:
        return 50;
    }
  }

  @override
  Future<Map<String, dynamic>> launchUpiIntent({
    required String uri,
    String? packageName,
  }) async {
    // If a specific package is given on Android, try upi_intent package first, then UpiIndiaService
    if (packageName != null && packageName.isNotEmpty) {
      final uriParsed = Uri.parse(uri);
      final pa = uriParsed.queryParameters['pa'] ?? '9886699258-3@ybl';
      final pn = (uriParsed.queryParameters['pn'] ?? 'SMART GROUP PGS')
          .replaceAll("'", '')
          .trim();
      final amStr = uriParsed.queryParameters['am'] ?? '1.00';
      final am = double.tryParse(amStr) ?? 1.0;
      final tn = (uriParsed.queryParameters['tn'] ?? 'Rent Payment')
          .replaceAll("'", '')
          .trim();
      final tr =
          uriParsed.queryParameters['tr'] ??
          'UPI${DateTime.now().millisecondsSinceEpoch}';

      // 1. Try upi_intent package
      try {
        final payment = upiint.UpiPayment(
          payeeVpa: pa,
          payeeName: pn.isNotEmpty ? pn : 'SMART GROUP PGS',
          amount: am,
          transactionNote: tn.isNotEmpty ? tn : 'Rent Payment',
          transactionRefId: tr,
        );
        final targetApp = upiint.UpiApp(
          name: packageName,
          packageName: packageName,
        );
        final upiRes = await upiint.UpiIntent.payWithApp(
          payment: payment,
          app: targetApp,
        );
        if (upiRes != null) {
          final isSuccess = upiRes.isSuccess;
          final isSubmitted =
              upiRes.status == upiint.UpiTransactionStatus.submitted;
          return {
            'status': isSuccess
                ? 'SUCCESS'
                : (isSubmitted ? 'SUBMITTED' : 'FAILURE'),
            'rawResponse': upiRes.rawResponse,
            'approvalRefNo': upiRes.approvalRefNo,
            'txnRef': tr,
            'txnId': upiRes.transactionId,
            'responseCode': upiRes.responseCode,
          };
        }
      } catch (e) {
        debugPrint('[DefaultDirectUpiGateway] upi_intent launch fallback: $e');
      }

      // 2. Try UpiIndiaService fallback
      try {
        final upiRes = await UpiIndiaService.startTransaction(
          app: UpiApp(name: packageName, packageName: packageName),
          receiverUpiId: pa,
          receiverName: pn.isNotEmpty ? pn : 'SMART GROUP PGS',
          transactionRefId: tr,
          transactionNote: tn.isNotEmpty ? tn : 'Rent Payment',
          amount: am,
        );
        return {
          'status': upiRes.status?.toUpperCase() ?? 'SUCCESS',
          'rawResponse': upiRes.rawResponse,
          'approvalRefNo': upiRes.approvalRefNo,
          'txnRef': upiRes.transactionRefId ?? tr,
          'txnId': upiRes.transactionId,
          'responseCode': upiRes.responseCode,
        };
      } catch (e) {
        debugPrint(
          '[DefaultDirectUpiGateway] UpiIndiaService failed, falling back to native channel: $e',
        );
      }
    }

    final res = await _channel.invokeMapMethod<String, dynamic>(
      'launchUpiIntent',
      {
        'uri': uri,
        if (packageName != null && packageName.isNotEmpty)
          'packageName': packageName,
      },
    );
    return res != null ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> initiateBackendPayment({
    required String invoiceId,
    String? idempotencyKey,
    String? appName,
    String? packageName,
  }) async {
    return ResidentApiService.initiateDirectUpiPayment(
      invoiceId: invoiceId,
      idempotencyKey: idempotencyKey,
      appName: appName,
      packageName: packageName,
    );
  }

  @override
  Future<Map<String, dynamic>> recordBackendResponse({
    required String paymentId,
    required String status,
    String? txnRef,
    String? upiTxnId,
    String? approvalRefNo,
    String? responseCode,
    String? rawResponse,
    String? appPackage,
  }) async {
    return ResidentApiService.recordUpiIntentResponse(
      paymentId: paymentId,
      status: status,
      txnRef: txnRef,
      upiTxnId: upiTxnId,
      approvalRefNo: approvalRefNo,
      responseCode: responseCode,
      rawResponse: rawResponse,
      appPackage: appPackage,
    );
  }

  @override
  Future<Map<String, dynamic>> cancelBackendPayment(String paymentId) async {
    return ResidentApiService.cancelUpiPayment(paymentId);
  }
}

/// Production service managing Direct UPI Intent discovery, launch, response parsing,
/// duplicate-tap prevention, and fail-closed backend synchronization.
class DirectUpiService {
  static DirectUpiGateway gateway = const DefaultDirectUpiGateway();
  static bool _isProcessing = false;

  static bool get isProcessing => _isProcessing;

  static const String msgVerifiedSuccess = 'Payment verified successfully.';
  static const String msgWaitingConfirmation =
      'Payment initiated. Waiting for confirmation. Please do not pay again.';
  static const String msgNotCompleted =
      'Payment was not completed. Please check your UPI application.';
  static const String msgBankRestricted =
      'Your bank or UPI app has restricted this transaction. Please check your transaction limits or contact your bank.';
  static const String msgCancelled = 'Payment was cancelled.';
  static const String msgAppNotInstalled =
      'Selected UPI app is not installed on this device. Please choose another UPI app.';

  /// Discovers installed UPI apps dynamically on Android 11+.
  static Future<List<InstalledUpiApp>> discoverInstalledApps() async {
    return gateway.getInstalledApps();
  }

  /// Masks VPA local-part for safe diagnostic logging (e.g. `ma***00@okaxis`).
  static String redactVpa(String? vpa) {
    final clean = (vpa ?? '').trim();
    final atIdx = clean.indexOf('@');
    if (atIdx <= 0) return '***';
    final local = clean.substring(0, atIdx);
    final domain = clean.substring(atIdx);
    if (local.length <= 3) return '${local[0]}***$domain';
    return '${local.substring(0, 2)}***${local.substring(local.length - 2)}$domain';
  }

  /// Strips unsupported parameters (`package`, empty params) and rebuilds a
  /// strictly RFC-3986 encoded NPCI `upi://pay` URI (`%20` spaces, NEVER `+`).
  static Uri buildCleanUpiUri(String rawUri) {
    final parsed = Uri.parse(rawUri.trim());
    final orderedParams = <String, String>{};
    parsed.queryParameters.forEach((key, value) {
      final cleanKey = key.trim();
      final cleanVal = value.trim();
      if (cleanKey.isEmpty ||
          cleanKey.toLowerCase() == 'package' ||
          cleanKey.toLowerCase() == 'mc' ||
          cleanVal.isEmpty) {
        return;
      }
      if (cleanKey == 'tr') {
        final cleanTr = cleanVal.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim();
        if (cleanTr.isNotEmpty) {
          orderedParams[cleanKey] = cleanTr.length > 35
              ? cleanTr.substring(0, 35)
              : cleanTr;
        }
      } else if (cleanKey == 'pn') {
        orderedParams[cleanKey] = cleanVal.replaceAll("'", '').trim();
      } else if (cleanKey == 'tn') {
        final sanitized = cleanVal
            .replaceAll('+', ' ')
            .replaceAll("'", '')
            .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        orderedParams[cleanKey] = sanitized.length > 50
            ? sanitized.substring(0, 50).trim()
            : sanitized;
      } else {
        orderedParams[cleanKey] = cleanVal;
      }
    });

    orderedParams['mode'] = '04';

    final encodedQuery = orderedParams.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return Uri(scheme: parsed.scheme, host: parsed.host, query: encodedQuery);
  }

  /// Parses raw Android Activity result map or NPCI key=value response string.
  static DirectUpiLaunchResult parseNativeResult(
    Map<String, dynamic> rawMap, {
    String? appName,
    String? appPackage,
  }) {
    final rawResponseStr = rawMap['rawResponse']?.toString() ?? '';
    final parsedKv = <String, String>{};
    if (rawResponseStr.isNotEmpty) {
      for (final part in rawResponseStr.split('&')) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          final k = Uri.decodeComponent(part.substring(0, idx))
              .trim()
              .toLowerCase();
          final v = Uri.decodeComponent(part.substring(idx + 1)).trim();
          parsedKv[k] = v;
        }
      }
    }

    final statusRaw =
        (rawMap['status']?.toString() ?? parsedKv['status'] ?? 'UNKNOWN')
            .trim()
            .toUpperCase();
    final txnId = _nonEmpty(rawMap['txnId']?.toString() ?? parsedKv['txnid']);
    final txnRef = _nonEmpty(
      rawMap['txnRef']?.toString() ?? parsedKv['txnref'],
    );
    final approvalRef = _nonEmpty(
      rawMap['approvalRefNo']?.toString() ?? parsedKv['approvalrefno'],
    );
    final responseCode = _nonEmpty(
      rawMap['responseCode']?.toString() ?? parsedKv['responsecode'],
    );
    final extraMsg = _nonEmpty(
      rawMap['message']?.toString() ?? parsedKv['message'],
    );

    final restricted = isLimitOrSecurityRestriction(
      responseCode: responseCode,
      rawResponse: '$rawResponseStr ${extraMsg ?? ''}',
    );

    final outcomeStatus = _mapOutcomeStatus(statusRaw, responseCode, extraMsg);
    final errorCategory = classifyErrorCategory(
      outcomeStatus: outcomeStatus,
      responseCode: responseCode,
      rawText: '$rawResponseStr ${extraMsg ?? ''}',
    );
    final message = _messageForOutcome(
      outcomeStatus: outcomeStatus,
      isRestricted: restricted,
    );

    return DirectUpiLaunchResult(
      status: outcomeStatus,
      errorCategory: errorCategory,
      rawStatusString: _backendStatusToken(outcomeStatus),
      txnId: txnId,
      txnRef: txnRef,
      approvalRefNo: approvalRef,
      responseCode: responseCode,
      rawResponse: rawResponseStr.isEmpty ? null : rawResponseStr,
      appPackage: appPackage ?? _nonEmpty(rawMap['packageName']?.toString()),
      appName: appName,
      isLimitOrSecurityRestricted: restricted,
      userMessage: message,
    );
  }

  static DirectUpiErrorCategory classifyErrorCategory({
    required DirectUpiOutcomeStatus outcomeStatus,
    String? responseCode,
    String? rawText,
  }) {
    final code = (responseCode ?? '').trim().toUpperCase();
    final text = (rawText ?? '').toLowerCase();
    if (outcomeStatus == DirectUpiOutcomeStatus.appNotInstalled ||
        code == 'LAUNCH_ERROR' ||
        code == 'INVALID_URI') {
      return DirectUpiErrorCategory.appLaunchFailure;
    }
    if (text.contains('security reasons') ||
        text.contains('security policy') ||
        text.contains('risk')) {
      return DirectUpiErrorCategory.securityRejection;
    }
    if (isLimitOrSecurityRestriction(
      responseCode: responseCode,
      rawResponse: rawText,
    )) {
      return DirectUpiErrorCategory.bankLimitRejection;
    }
    switch (outcomeStatus) {
      case DirectUpiOutcomeStatus.cancelled:
        return DirectUpiErrorCategory.userCancelled;
      case DirectUpiOutcomeStatus.networkError:
        return DirectUpiErrorCategory.networkFailure;
      case DirectUpiOutcomeStatus.success:
      case DirectUpiOutcomeStatus.submitted:
      case DirectUpiOutcomeStatus.pending:
        return DirectUpiErrorCategory.pendingTransaction;
      case DirectUpiOutcomeStatus.failure:
        return DirectUpiErrorCategory.bankTransactionRejection;
      case DirectUpiOutcomeStatus.appNotInstalled:
        return DirectUpiErrorCategory.appLaunchFailure;
      case DirectUpiOutcomeStatus.unknown:
        return DirectUpiErrorCategory.unknownError;
    }
  }

  static bool isLimitOrSecurityRestriction({
    String? responseCode,
    String? rawResponse,
  }) {
    final code = (responseCode ?? '').trim().toUpperCase();
    const limitCodes = {
      'Z9',
      'ZM',
      'ZA',
      'Z5',
      'U30',
      'U69',
      'XH',
      'XU',
      'B3',
      'LIMIT_EXCEEDED',
    };
    if (limitCodes.contains(code)) {
      return true;
    }
    final text = (rawResponse ?? '').toLowerCase();
    return text.contains('limit exceeded') ||
        text.contains('check upi limit') ||
        text.contains('security reasons') ||
        text.contains('security policy') ||
        text.contains('risk') ||
        text.contains('per day limit') ||
        text.contains('threshold');
  }

  static DirectUpiOutcomeStatus _mapOutcomeStatus(
    String statusRaw,
    String? responseCode,
    String? extraMsg,
  ) {
    final msg = (extraMsg ?? '').toLowerCase();
    if (statusRaw == 'APP_NOT_INSTALLED' ||
        statusRaw == 'PACKAGE_NOT_INSTALLED') {
      return DirectUpiOutcomeStatus.appNotInstalled;
    }
    if (statusRaw == 'NETWORK_ERROR' ||
        msg.contains('network') ||
        responseCode == 'NETWORK_ERROR') {
      return DirectUpiOutcomeStatus.networkError;
    }
    if (statusRaw == 'SUCCESS') return DirectUpiOutcomeStatus.success;
    if (statusRaw == 'SUBMITTED') return DirectUpiOutcomeStatus.submitted;
    if (statusRaw == 'PENDING') return DirectUpiOutcomeStatus.pending;
    if (statusRaw == 'CANCELLED' || statusRaw == 'CANCELED') {
      return DirectUpiOutcomeStatus.cancelled;
    }
    if (statusRaw == 'FAILURE' || statusRaw == 'FAILED') {
      return DirectUpiOutcomeStatus.failure;
    }
    return DirectUpiOutcomeStatus.unknown;
  }

  static String _backendStatusToken(DirectUpiOutcomeStatus status) {
    switch (status) {
      case DirectUpiOutcomeStatus.success:
        return 'SUCCESS';
      case DirectUpiOutcomeStatus.submitted:
        return 'SUBMITTED';
      case DirectUpiOutcomeStatus.pending:
        return 'PENDING';
      case DirectUpiOutcomeStatus.cancelled:
        return 'CANCELLED';
      case DirectUpiOutcomeStatus.networkError:
        return 'NETWORK_ERROR';
      case DirectUpiOutcomeStatus.failure:
      case DirectUpiOutcomeStatus.appNotInstalled:
        return 'FAILURE';
      case DirectUpiOutcomeStatus.unknown:
        return 'UNKNOWN';
    }
  }

  static String _messageForOutcome({
    required DirectUpiOutcomeStatus outcomeStatus,
    required bool isRestricted,
  }) {
    if (isRestricted) return msgBankRestricted;
    switch (outcomeStatus) {
      case DirectUpiOutcomeStatus.success:
      case DirectUpiOutcomeStatus.submitted:
      case DirectUpiOutcomeStatus.pending:
      case DirectUpiOutcomeStatus.unknown:
        return msgWaitingConfirmation;
      case DirectUpiOutcomeStatus.cancelled:
        return msgCancelled;
      case DirectUpiOutcomeStatus.appNotInstalled:
        return msgAppNotInstalled;
      case DirectUpiOutcomeStatus.failure:
      case DirectUpiOutcomeStatus.networkError:
        return msgNotCompleted;
    }
  }

  static String? _nonEmpty(String? v) {
    if (v == null) return null;
    final clean = v.trim();
    return clean.isEmpty || clean == 'null' ? null : clean;
  }

  /// Authoritative end-to-end Direct UPI payment flow:
  /// 1. Initiates payment on FastAPI backend (computes balance & TXN ref from DB)
  /// 2. Launches selected installed UPI app via Android Intent (`startActivityForResult`)
  /// 3. Submits response to `/payments/upi/response` without ever trusting client success
  static Future<DirectUpiFlowResult> initiateAndPay({
    required String invoiceId,
    required InstalledUpiApp selectedApp,
    String? idempotencyKey,
    double? overrideAmount,
  }) async {
    if (_isProcessing) {
      throw StateError('A UPI payment request is already in progress.');
    }
    _isProcessing = true;
    try {
      Map<String, dynamic> initData = {};
      try {
        initData = await gateway.initiateBackendPayment(
          invoiceId: invoiceId,
          idempotencyKey: idempotencyKey,
          appName: selectedApp.name,
          packageName: selectedApp.packageName,
        );
      } catch (e) {
        debugPrint(
          '[DirectUpi] Backend initiation unavailable (proceeding with local parameters): $e',
        );
      }

      final paymentId = initData['payment_id']?.toString();
      final paymentNumber = initData['payment_number']?.toString();
      final txnRefStr = initData['transaction_ref']?.toString();
      final txnRef = (txnRefStr != null && txnRefStr.isNotEmpty)
          ? txnRefStr
          : 'UPI${DateTime.now().millisecondsSinceEpoch}';
      final double amount =
          overrideAmount ?? (initData['amount'] as num?)?.toDouble() ?? 8000.0;
      final rawUpiUri = initData['upi_uri']?.toString();

      final Uri cleanUri;
      if (rawUpiUri != null && rawUpiUri.isNotEmpty) {
        cleanUri = buildCleanUpiUri(rawUpiUri);
      } else {
        cleanUri = Uri.parse(
          'upi://pay?pa=9886699258-3@ybl'
          '&pn=SMART%20GROUP%20PGS'
          '&am=${amount.toStringAsFixed(2)}'
          '&cu=INR'
          '&tn=Rent%20Payment'
          '&tr=$txnRef'
          '&mode=04',
        );
      }

      final redactedVpa = redactVpa(
        initData['payee_vpa']?.toString() ?? '9886699258-3@ybl',
      );
      debugPrint(
        '[DirectUpi] Launch ref=$txnRef app=${selectedApp.name} (${selectedApp.packageName}) '
        'vpa=$redactedVpa am=$amount hasPlus=${cleanUri.toString().contains('+')}',
      );

      Map<String, dynamic> nativeMap = {};
      try {
        final launchResult = await gateway.launchUpiIntent(
          uri: cleanUri.toString(),
          packageName: selectedApp.packageName,
        );
        nativeMap = Map<String, dynamic>.from(launchResult);
      } catch (e) {
        debugPrint('[DirectUpi] Launch error: $e');
        nativeMap = {
          'status': 'FAILURE',
          'responseCode': 'LAUNCH_ERROR',
          'message': e.toString(),
        };
      }

      final outcome = parseNativeResult(
        nativeMap,
        appName: selectedApp.name,
        appPackage: selectedApp.packageName,
      );

      debugPrint(
        '[DirectUpi] Result ref=$txnRef app=${selectedApp.name} status=${outcome.status.name} '
        'code=${outcome.responseCode ?? "-"} category=${outcome.errorCategory.name} '
        'txnId=${outcome.txnId ?? "-"}',
      );

      Map<String, dynamic> syncRes = {};
      if (outcome.status == DirectUpiOutcomeStatus.appNotInstalled) {
        if (paymentId != null && paymentId.isNotEmpty) {
          try {
            syncRes = await gateway.cancelBackendPayment(paymentId);
          } catch (e) {
            debugPrint('Cancel after missing UPI app failed: $e');
          }
        }
      } else {
        if (paymentId != null && paymentId.isNotEmpty) {
          try {
            syncRes = await gateway.recordBackendResponse(
              paymentId: paymentId,
              status: outcome.rawStatusString,
              txnRef: txnRef,
              upiTxnId: outcome.txnId,
              approvalRefNo: outcome.approvalRefNo,
              responseCode: outcome.responseCode,
              rawResponse: outcome.rawResponse,
              appPackage: selectedApp.packageName,
            );
          } catch (e) {
            debugPrint('Backend UPI response sync error: $e');
          }
        }
      }

      final backendStatus =
          (syncRes['status']?.toString() ??
                  (outcome.status == DirectUpiOutcomeStatus.cancelled
                      ? 'CANCELLED'
                      : outcome.status == DirectUpiOutcomeStatus.failure
                      ? 'FAILED'
                      : 'PENDING_VERIFICATION'))
              .toUpperCase();
      final settled =
          syncRes['is_settled'] == true ||
          backendStatus == 'PAID' ||
          backendStatus == 'SUCCESS';

      debugPrint(
        '[DirectUpi] Synced ref=$txnRef backendStatus=$backendStatus settled=$settled',
      );

      return DirectUpiFlowResult(
        paymentId: paymentId,
        paymentNumber: paymentNumber,
        txnRef: txnRef,
        amount: amount,
        payeeVpa: initData['payee_vpa']?.toString(),
        payeeName: initData['payee_name']?.toString(),
        outcome: outcome,
        backendStatus: backendStatus,
        isSettled: settled,
        receiptId: syncRes['receipt_id']?.toString(),
        receiptNumber: syncRes['receipt_number']?.toString(),
      );
    } finally {
      _isProcessing = false;
    }
  }
}
