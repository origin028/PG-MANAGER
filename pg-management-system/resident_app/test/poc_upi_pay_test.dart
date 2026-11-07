import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upi_pay/upi_pay.dart' as upi;
import 'package:resident_app/features/payments/poc_upi_pay_service.dart';
import 'package:resident_app/features/payments/poc_upi_pay_screen.dart';

final Uint8List testIconBytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAA=');

/// Mock Runner implementation for isolated unit testing
class MockPocUpiPayRunner implements PocUpiPayRunner {
  List<upi.ApplicationMeta> mockApps;
  upi.UpiTransactionResponse? mockResponse;
  bool isGooglePayInstalled;
  bool isPhonePeInstalled;
  bool isNaviInstalled;
  Map<String, dynamic>? mockNativePhonePeResult;

  MockPocUpiPayRunner({
    this.mockApps = const [],
    this.mockResponse,
    this.isGooglePayInstalled = true,
    this.isPhonePeInstalled = true,
    this.isNaviInstalled = true,
    this.mockNativePhonePeResult = const {'status': 'SUCCESS', 'method': 'EXPLICIT_UPI_INTENT'},
  });

  @override
  Future<List<upi.ApplicationMeta>> getInstalledUpiApplications({
    upi.UpiApplicationDiscoveryAppStatusType statusType =
        upi.UpiApplicationDiscoveryAppStatusType.all,
  }) async {
    return mockApps;
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
    if (mockResponse != null) {
      return mockResponse!;
    }
    return upi.UpiTransactionResponse.android(
      'txnId=UPI12345&responseCode=00&approvalRefNo=REF98765&status=SUCCESS&txnRef=$transactionRef',
    );
  }

  @override
  Future<bool> checkPackageInstalledNative(String packageName) async {
    if (packageName == PocUpiPayService.googlePayPackage) return isGooglePayInstalled;
    if (packageName == PocUpiPayService.phonePePackage) return isPhonePeInstalled;
    if (packageName == PocUpiPayService.naviPackage) return isNaviInstalled;
    return false;
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
    return mockNativePhonePeResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    PocUpiPayService.runner = const DefaultPocUpiPayRunner();
  });

  group('PocUpiPayService Unit Tests', () {
    test('Payee configuration matches verified PG credentials', () {
      expect(PocUpiPayService.verifiedPayeeVpa, 'masisokatali90900@okaxis');
      expect(PocUpiPayService.verifiedPayeeName, 'Saukatali Masi');
      expect(PocUpiPayService.defaultCurrency, 'INR');
      expect(PocUpiPayService.googlePayPackage, 'com.google.android.apps.nbu.paisa.user');
      expect(PocUpiPayService.phonePePackage, 'com.phonepe.app');
      expect(PocUpiPayService.naviPackage, 'com.navi.curiosity');
    });

    test('Navi custom UpiApplication is configured correctly with com.navi.curiosity', () {
      final navi = PocUpiPayService.naviCustomApplication;
      expect(navi.androidPackageName, 'com.navi.curiosity');
      expect(navi.appName, 'Navi');
      expect(navi.toString(), 'com.navi.curiosity');
    });

    test('discoverInstalledApps discovers apps returned by upi_pay with statusType.all and resolves Navi separately', () async {
      final mock = MockPocUpiPayRunner(
        mockApps: [
          upi.ApplicationMeta.android(
            upi.UpiApplication.googlePay,
            testIconBytes,
            1,
            1,
          ),
        ],
        isPhonePeInstalled: true,
        isNaviInstalled: true,
      );
      PocUpiPayService.runner = mock;

      final discovered = await PocUpiPayService.discoverInstalledApps();

      // Should discover Google Pay from upi_pay
      final gpay = discovered.firstWhere((a) => a.packageName == PocUpiPayService.googlePayPackage);
      expect(gpay.appName, 'Google Pay');
      expect(gpay.isNativelySupportedByPackage, isTrue);

      // Should discover PhonePe via auxiliary native check
      final phonepe = discovered.firstWhere((a) => a.packageName == PocUpiPayService.phonePePackage);
      expect(phonepe.appName, 'PhonePe');
      expect(phonepe.isNativelySupportedByPackage, isTrue);

      // Should discover Navi via custom application resolution
      final navi = discovered.firstWhere((a) => a.packageName == PocUpiPayService.naviPackage);
      expect(navi.appName, 'Navi UPI');
      expect(navi.isNativelySupportedByPackage, isFalse);
    });

    test('initiatePocPayment for Google Pay launches ₹1.00 and records PENDING_VERIFICATION', () async {
      final mock = MockPocUpiPayRunner(
        mockResponse: upi.UpiTransactionResponse.android(
          'txnId=GPAY9988&responseCode=00&approvalRefNo=AUTH123&status=SUCCESS&txnRef=TXN-GPAY-1',
        ),
      );
      PocUpiPayService.runner = mock;

      final result = await PocUpiPayService.initiatePocPayment(
        appName: 'Google Pay',
        packageName: PocUpiPayService.googlePayPackage,
        upiApp: upi.UpiApplication.googlePay,
        invoiceId: 'INV-TEST-001',
        amount: 1.00,
      );

      expect(result.appName, 'Google Pay');
      expect(result.packageName, PocUpiPayService.googlePayPackage);
      expect(result.amount, 1.00);
      expect(result.launched, isTrue);
      expect(result.status, upi.UpiTransactionStatus.success);
      expect(result.responseCode, '00');
      expect(result.approvalRefNo, 'AUTH123');
      expect(result.verificationState, 'pendingVerification');
      expect(result.generatedUri, contains('pa=masisokatali90900@okaxis'));
      expect(result.generatedUri, contains('am=1.00'));
      expect(result.generatedUri, contains('mode=00'));

      // Verify transaction state in SharedPreferences remains pendingVerification
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pg_payment_tx_INV-TEST-001');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['state'], 'pendingVerification');
      expect(json['amount'], 1.00);
    });

    test('initiatePocPayment handles activity_unavailable for PhonePe and triggers native fallback when enabled', () async {
      final mock = MockPocUpiPayRunner(
        mockResponse: upi.UpiTransactionResponse.android('activity_unavailable'),
        mockNativePhonePeResult: {'status': 'SUCCESS', 'method': 'EXPLICIT_UPI_INTENT'},
      );
      PocUpiPayService.runner = mock;

      final result = await PocUpiPayService.initiatePocPayment(
        appName: 'PhonePe',
        packageName: PocUpiPayService.phonePePackage,
        upiApp: upi.UpiApplication.phonePe,
        invoiceId: 'INV-TEST-PHONEPE',
        amount: 1.00,
        enableNativePhonePeFallback: true,
      );

      expect(result.appName, 'PhonePe');
      expect(result.rawResponse, 'activity_unavailable');
      // Launched becomes true because of native fallback
      expect(result.launched, isTrue);
      expect(result.message, contains('Launched PhonePe via Native Kotlin fallback'));
      expect(result.verificationState, 'pendingVerification');
    });

    test('initiatePocPayment without native fallback reports activity_unavailable cleanly', () async {
      final mock = MockPocUpiPayRunner(
        mockResponse: upi.UpiTransactionResponse.android('activity_unavailable'),
      );
      PocUpiPayService.runner = mock;

      final result = await PocUpiPayService.initiatePocPayment(
        appName: 'PhonePe',
        packageName: PocUpiPayService.phonePePackage,
        upiApp: upi.UpiApplication.phonePe,
        invoiceId: 'INV-TEST-PHONEPE-NOFB',
        amount: 1.00,
        enableNativePhonePeFallback: false,
      );

      expect(result.launched, isFalse);
      expect(result.message, contains('has no activity resolving standard upi://pay intent'));
      expect(result.verificationState, 'pendingVerification');
    });

    test('initiatePocPayment for Navi uses custom UpiApplication and records PENDING_VERIFICATION', () async {
      final mock = MockPocUpiPayRunner(
        mockResponse: upi.UpiTransactionResponse.android(
          'txnId=NAVI77&responseCode=00&approvalRefNo=NAVIREF1&status=SUCCESS&txnRef=TXN-NAVI-1',
        ),
      );
      PocUpiPayService.runner = mock;

      final result = await PocUpiPayService.initiatePocPayment(
        appName: 'Navi UPI',
        packageName: PocUpiPayService.naviPackage,
        upiApp: PocUpiPayService.naviCustomApplication,
        invoiceId: 'INV-TEST-NAVI',
        amount: 1.00,
      );

      expect(result.appName, 'Navi UPI');
      expect(result.packageName, 'com.navi.curiosity');
      expect(result.launched, isTrue);
      expect(result.status, upi.UpiTransactionStatus.success);
      expect(result.verificationState, 'pendingVerification');
    });

    test('initiatePocPayment handles user_cancelled gracefully', () async {
      final mock = MockPocUpiPayRunner(
        mockResponse: upi.UpiTransactionResponse.android('user_cancelled'),
      );
      PocUpiPayService.runner = mock;

      final result = await PocUpiPayService.initiatePocPayment(
        appName: 'Google Pay',
        packageName: PocUpiPayService.googlePayPackage,
        upiApp: upi.UpiApplication.googlePay,
        invoiceId: 'INV-TEST-CANCEL',
        amount: 1.00,
      );

      expect(result.launched, isTrue);
      expect(result.rawResponse, 'user_cancelled');
      expect(result.message, contains('Cancelled'));
      expect(result.verificationState, 'pendingVerification');
    });
  });

  group('PocUpiPayScreen Widget Tests', () {
    testWidgets('Renders PocUpiPayScreen, safe test invoice banner, apps list, and test action tiles', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockPocUpiPayRunner(
        mockApps: [
          upi.ApplicationMeta.android(
            upi.UpiApplication.googlePay,
            testIconBytes,
            1,
            1,
          ),
          upi.ApplicationMeta.android(
            upi.UpiApplication.phonePe,
            testIconBytes,
            2,
            2,
          ),
        ],
        isGooglePayInstalled: true,
        isPhonePeInstalled: true,
        isNaviInstalled: true,
      );
      PocUpiPayService.runner = mock;

      await tester.pumpWidget(
        const MaterialApp(
          home: PocUpiPayScreen(
            invoiceData: {
              'id': 'INV-2026-TEST',
              'amount': 1.00,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner checks
      expect(find.text('upi_pay Package Evaluation POC'), findsOneWidget);
      expect(find.text('Test Invoice: INV-2026-TEST (₹1.00)'), findsOneWidget);
      expect(find.textContaining('Saukatali Masi'), findsWidgets);
      expect(find.textContaining('masisokatali90900@okaxis'), findsWidgets);

      // Discovered Apps checks
      expect(find.textContaining('Discovered UPI Apps'), findsOneWidget);
      expect(find.text('Google Pay'), findsWidgets);
      expect(find.text('PhonePe'), findsWidgets);
      expect(find.text('Navi UPI'), findsWidgets);

      // Test tiles checks
      expect(find.text('1. Test Google Pay via upi_pay'), findsOneWidget);
      expect(find.text('2. Test PhonePe via upi_pay'), findsOneWidget);
      expect(find.text('3. Test Navi UPI via Custom upi_pay App'), findsOneWidget);

      // Execute Google Pay test launch
      await tester.tap(find.text('Test ₹1').first);
      await tester.pumpAndSettle();

      // Result card should appear with PENDING_VERIFICATION badge
      expect(find.text('Execution Result: Google Pay'), findsOneWidget);
      expect(find.text('LAUNCHED'), findsOneWidget);
      expect(find.text('State: PENDING_VERIFICATION (Invoice not marked paid on callback)'), findsOneWidget);
    });
  });
}
