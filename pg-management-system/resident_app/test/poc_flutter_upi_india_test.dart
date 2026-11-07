import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_upi_india/flutter_upi_india.dart';
import 'package:resident_app/features/payments/poc_flutter_upi_service.dart';
import 'package:resident_app/features/payments/poc_flutter_upi_screen.dart';

class MockPocUpiRunner implements PocUpiRunner {
  List<ApplicationMeta> appsToReturn;
  UpiTransactionResponse? responseToReturn;
  Object? exceptionToThrow;
  bool launchUrlResult;

  UpiApplication? lastApp;
  String? lastReceiverUpi;
  String? lastReceiverName;
  String? lastTxnRef;
  String? lastAmount;
  String? lastNote;
  Uri? lastLaunchedUri;

  MockPocUpiRunner({
    this.appsToReturn = const [],
    this.responseToReturn,
    this.exceptionToThrow,
    this.launchUrlResult = true,
  });

  @override
  Future<List<ApplicationMeta>> getInstalledApps() async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return appsToReturn;
  }

  @override
  Future<UpiTransactionResponse> initiateTransaction({
    required UpiApplication app,
    required String receiverUpiAddress,
    required String receiverName,
    required String transactionRef,
    required String amount,
    String? transactionNote,
  }) async {
    lastApp = app;
    lastReceiverUpi = receiverUpiAddress;
    lastReceiverName = receiverName;
    lastTxnRef = transactionRef;
    lastAmount = amount;
    lastNote = transactionNote;

    if (exceptionToThrow != null) throw exceptionToThrow!;
    return responseToReturn ?? UpiTransactionResponse.android('status=failure&responseCode=U16');
  }

  @override
  Future<bool> launchUrlExternal(Uri uri) async {
    lastLaunchedUri = uri;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return launchUrlResult;
  }
}

void main() {
  setUp(() {
    PocFlutterUpiService.runner = const DefaultPocUpiRunner();
  });

  tearDown(() {
    PocFlutterUpiService.runner = const DefaultPocUpiRunner();
  });

  group('PocFlutterUpiService Multi-Approach Unit Tests', () {
    test('Payee configuration matches verified PG Management credentials', () {
      expect(PocFlutterUpiService.verifiedPayeeVpa, 'masisokatali90900@okaxis');
      expect(PocFlutterUpiService.verifiedPayeeName, "Saukatali Masi");
      expect(PocFlutterUpiService.defaultCurrency, 'INR');
      expect(PocFlutterUpiService.googlePayPackage, 'com.google.android.apps.nbu.paisa.user');
    });

    test('buildStandardUpiUri builds RFC compliant NPCI URI with package option', () {
      final uri = PocFlutterUpiService.buildStandardUpiUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: "Saukatali Masi",
        amount: 1.00,
        transactionRef: 'TXN-TEST-1',
        transactionNote: 'Test Note',
        targetedPackage: 'com.google.android.apps.nbu.paisa.user',
      );

      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'masisokatali90900@okaxis');
      expect(uri.queryParameters['pn'], "Saukatali Masi");
      expect(uri.queryParameters['am'], '1.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tr'], 'TXN-TEST-1');
      expect(uri.queryParameters['package'], 'com.google.android.apps.nbu.paisa.user');
    });

    test('Approach 1: executeTargetedIntent launches Google Pay package directly and notes Mode 04', () async {
      final mock = MockPocUpiRunner(launchUrlResult: true);
      PocFlutterUpiService.runner = mock;

      final res = await PocFlutterUpiService.executeTargetedIntent(
        invoiceId: 'INV-TEST-001',
        amount: 1.00,
      );

      expect(res.approach, UpiApproach.packageTargetedUrlLauncher);
      expect(res.npciInitiationMode, '04');
      expect(res.appLaunchSuccess, isTrue);
      expect(res.bankTransactionSuccess, isFalse);
      expect(res.isBankLimitError, isTrue);
      expect(mock.lastLaunchedUri?.queryParameters['package'], 'com.google.android.apps.nbu.paisa.user');
      expect(res.verificationState, 'PENDING_VERIFICATION');
    });

    test('Approach 2: executeGenericChooserIntent launches universal URI without package', () async {
      final mock = MockPocUpiRunner(launchUrlResult: true);
      PocFlutterUpiService.runner = mock;

      final res = await PocFlutterUpiService.executeGenericChooserIntent(
        invoiceId: 'INV-TEST-002',
        amount: 1.00,
      );

      expect(res.approach, UpiApproach.genericChooserUrlLauncher);
      expect(res.npciInitiationMode, '04');
      expect(res.appLaunchSuccess, isTrue);
      expect(mock.lastLaunchedUri?.queryParameters.containsKey('package'), isFalse);
    });

    test('Approach 3: executeActivityResultIntent captures U16 limit error via flutter_upi_india', () async {
      final mock = MockPocUpiRunner(
        responseToReturn: UpiTransactionResponse.android(
          'txnId=&responseCode=U16&ApprovalRefNo=&Status=FAILURE&txnRef=POC-ACT-001',
        ),
      );
      PocFlutterUpiService.runner = mock;

      final res = await PocFlutterUpiService.executeActivityResultIntent(
        invoiceId: 'INV-TEST-003',
        amount: 1.00,
      );

      expect(res.approach, UpiApproach.activityForResultPackage);
      expect(res.status, PocPaymentStatus.failure);
      expect(res.responseCode, 'U16');
      expect(res.isBankLimitError, isTrue);
      expect(res.bankTransactionSuccess, isFalse);
    });

    test('Approach 4: executeAutoCopyAndLaunch enables Mode 00 user push P2P which BoB approves', () async {
      final mock = MockPocUpiRunner(launchUrlResult: true);
      PocFlutterUpiService.runner = mock;

      final res = await PocFlutterUpiService.executeAutoCopyAndLaunch(
        invoiceId: 'INV-TEST-004',
        amount: 1.00,
      );

      expect(res.approach, UpiApproach.autoCopyMode00);
      expect(res.npciInitiationMode, '00');
      expect(res.bankTransactionSuccess, isTrue);
      expect(res.verificationState, 'PENDING_VERIFICATION');
    });

    test('Approach 5: buildQrCodeData generates valid Mode 01 QR string for camera scanning', () {
      final qrString = PocFlutterUpiService.buildQrCodeData(
        invoiceId: 'INV-TEST-005',
        amount: 1.00,
      );

      expect(qrString.startsWith('upi://pay?'), isTrue);
      expect(qrString.contains('pa=masisokatali90900@okaxis'), isTrue);
      expect(qrString.contains('am=1.00'), isTrue);
    });

    test('Approach 6: getOfficialGooglePayApiSpec mandates Google Pay & Wallet Console and rejects personal VPA', () {
      final spec = PocFlutterUpiService.getOfficialGooglePayApiSpec(amount: 1.00);

      expect(spec['apiVersion'], 2);
      expect(spec['canUsePersonalVpa'], isFalse);
      expect(spec['documentationUrl'], 'https://developers.google.com/pay/india/api/android');
      final methods = spec['allowedPaymentMethods'] as List;
      expect(methods.first['type'], 'UPI');
    });
  });

  group('PocFlutterUpiScreen Widget Tests', () {
    testWidgets('Renders workbench, payee details, and allows approach switching', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockPocUpiRunner(launchUrlResult: true);
      PocFlutterUpiService.runner = mock;

      await tester.pumpWidget(
        const MaterialApp(
          home: PocFlutterUpiScreen(
            invoiceData: {
              'id': 'INV-TEST-001',
              'amount': 1.00,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('UPI Integration Workbench'), findsOneWidget);
      expect(find.text('₹ 1.00'), findsOneWidget);
      expect(find.text('masisokatali90900@okaxis'), findsOneWidget);
      expect(find.text("Saukatali Masi"), findsOneWidget);
      expect(find.text('1. Targeted Intent'), findsWidgets);
      expect(find.text('2. Generic Chooser'), findsOneWidget);
      expect(find.text('3. Result Intent'), findsOneWidget);
      expect(find.text('4. Auto-Copy + Launch'), findsOneWidget);
      expect(find.text('5. Dynamic QR Code'), findsOneWidget);
      expect(find.text('6. Official GPay API'), findsOneWidget);

      // Tap on Approach 4 (Auto-Copy)
      await tester.tap(find.text('4. Auto-Copy + Launch'));
      await tester.pumpAndSettle();

      expect(find.text('APPROVED (₹1L limit)'), findsWidgets);
    });

    testWidgets('Executing Approach 1 displays Bank Limit Exceeded (U16) diagnostic card', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockPocUpiRunner(launchUrlResult: true);
      PocFlutterUpiService.runner = mock;

      await tester.pumpWidget(
        const MaterialApp(
          home: PocFlutterUpiScreen(
            invoiceData: {
              'id': 'INV-TEST-001',
              'amount': 1.00,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final execBtn = find.text('Test 1. Targeted Intent');
      expect(execBtn, findsOneWidget);

      await tester.ensureVisible(execBtn);
      await tester.pumpAndSettle();

      await tester.tap(execBtn);
      await tester.pumpAndSettle();

      final statusFinder = find.text('BANK LIMIT EXCEEDED (U16)');
      await tester.ensureVisible(statusFinder);
      await tester.pumpAndSettle();

      expect(statusFinder, findsOneWidget);
      expect(find.text('Mode 04'), findsWidgets);
      expect(find.text('SUCCESS (Intent Dispatched)'), findsOneWidget);
      expect(find.text('REJECTED (Channel Limit ₹0.00)'), findsOneWidget);
    });
  });
}
