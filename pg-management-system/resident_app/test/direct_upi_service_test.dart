import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/services/direct_upi_service.dart';
import 'package:resident_app/features/payments/rent_payment_screen.dart';
import 'package:resident_app/features/payments/payment_status_screen.dart';

class MockDirectUpiGateway implements DirectUpiGateway {
  List<InstalledUpiApp> appsToReturn;
  Map<String, dynamic>? intentResult;
  Map<String, dynamic>? initResponse;
  Map<String, dynamic>? backendSyncResponse;
  Completer<Map<String, dynamic>>? pendingLaunchCompleter;

  String? launchedUri;
  String? launchedPackage;
  int initiateCallCount = 0;
  int responseSyncCount = 0;
  int cancelCallCount = 0;
  String? lastSyncedStatus;

  MockDirectUpiGateway({
    this.appsToReturn = const [
      InstalledUpiApp(name: 'Google Pay', packageName: 'com.google.android.apps.nbu.paisa.user'),
      InstalledUpiApp(name: 'PhonePe', packageName: 'com.phonepe.app'),
      InstalledUpiApp(name: 'Paytm', packageName: 'net.one97.paytm'),
      InstalledUpiApp(name: 'BHIM', packageName: 'in.org.npci.upiapp'),
    ],
    this.intentResult,
    this.initResponse,
    this.backendSyncResponse,
    this.pendingLaunchCompleter,
  });

  @override
  Future<List<InstalledUpiApp>> getInstalledApps() async => appsToReturn;

  @override
  Future<Map<String, dynamic>> initiateBackendPayment({
    required String invoiceId,
    String? idempotencyKey,
    String? appName,
    String? packageName,
  }) async {
    initiateCallCount++;
    return initResponse ??
        {
          'payment_id': '11111111-1111-1111-1111-111111111111',
          'payment_number': 'PAY-UPI-TEST001',
          'transaction_ref': 'TXNTEST123456',
          'amount': 8000,
          'payee_vpa': '9886699258-3@ybl',
          'payee_name': "SMART GROUP PG'S",
          'upi_uri':
              'upi://pay?pa=9886699258-3%40ybl&pn=SMART%20GROUP%20PGS&am=8000.00&cu=INR&tr=TXNTEST123456&tn=Rent%20Payment&package=com.phonepe.app',
        };
  }

  @override
  Future<Map<String, dynamic>> launchUpiIntent({
    required String uri,
    String? packageName,
  }) async {
    launchedUri = uri;
    launchedPackage = packageName;
    if (pendingLaunchCompleter != null) {
      return pendingLaunchCompleter!.future;
    }
    return intentResult ??
        {
          'status': 'SUCCESS',
          'txnId': 'UPI88990011',
          'responseCode': '00',
          'approvalRefNo': 'APR001',
          'rawResponse': 'txnId=UPI88990011&responseCode=00&Status=SUCCESS',
        };
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
    responseSyncCount++;
    lastSyncedStatus = status;
    return backendSyncResponse ??
        {
          'payment_id': paymentId,
          'status': (status == 'FAILURE' || status == 'NETWORK_ERROR')
              ? 'FAILED'
              : (status == 'CANCELLED' ? 'CANCELLED' : 'PENDING_VERIFICATION'),
          'is_settled': false,
        };
  }

  @override
  Future<Map<String, dynamic>> cancelBackendPayment(String paymentId) async {
    cancelCallCount++;
    return {'payment_id': paymentId, 'status': 'CANCELLED', 'is_settled': false};
  }
}

void main() {
  late DirectUpiGateway originalGateway;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    originalGateway = DirectUpiService.gateway;
    AppData.currentResident = {
      ...AppData.currentResident,
      'rent_status': 'Pending',
      'rent': 8000,
    };
  });

  tearDown(() {
    DirectUpiService.gateway = originalGateway;
  });

  group('DirectUpiService Unit Scenarios (Mocked Android Intent + Backend)', () {
    test('UPI Intent URI uses strict %20 encoding (never +), strips package, and caps note length', () {
      final clean = DirectUpiService.buildCleanUpiUri(
        'upi://pay?pa=9886699258-3%40ybl&pn=SMART%20GROUP%20PGS&am=8000.00&cu=INR&tr=TXN123&tn=Rent+Payment+08bd684a-aef1-4f11-ae43-6cd52a329c43+-+SMART+GROUP+PGS&package=com.phonepe.app',
      );
      expect(clean.scheme, 'upi');
      expect(clean.host, 'pay');
      expect(clean.queryParameters['pa'], '9886699258-3@ybl');
      expect(clean.queryParameters['pn'], 'SMART GROUP PGS');
      expect(clean.queryParameters['am'], '8000.00');
      expect(clean.queryParameters['cu'], 'INR');
      expect(clean.queryParameters['tr'], 'TXN123');
      expect(clean.queryParameters['tn']!.length, lessThanOrEqualTo(50));
      expect(clean.queryParameters['tn']!.contains('+'), isFalse);
      expect(clean.queryParameters.containsKey('package'), isFalse);
      expect(clean.toString().contains('+'), isFalse);
      expect(clean.toString(), contains('%20'));
      expect(DirectUpiService.redactVpa('9886699258-3@ybl'), '98***-3@ybl');
    });

    test('SUCCESS response stays PENDING_VERIFICATION and is NEVER auto-settled on client', () async {
      final mock = MockDirectUpiGateway(
        intentResult: {
          'status': 'SUCCESS',
          'txnId': 'UPI777888',
          'responseCode': '00',
          'rawResponse': 'txnId=UPI777888&responseCode=00&Status=SUCCESS',
        },
      );
      DirectUpiService.gateway = mock;

      final res = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-1',
        selectedApp: const InstalledUpiApp(
          name: 'Google Pay',
          packageName: 'com.google.android.apps.nbu.paisa.user',
        ),
      );

      expect(mock.launchedPackage, 'com.google.android.apps.nbu.paisa.user');
      expect(Uri.parse(mock.launchedUri!).queryParameters.containsKey('package'), isFalse);
      expect(mock.lastSyncedStatus, 'SUCCESS');
      expect(res.isSettled, isFalse);
      expect(res.backendStatus, 'PENDING_VERIFICATION');
      expect(res.canRetry, isFalse);
      expect(res.outcome.userMessage, DirectUpiService.msgWaitingConfirmation);
    });

    test('SUBMITTED, PENDING, and UNKNOWN responses remain PENDING_VERIFICATION without retry', () async {
      for (final rawStatus in ['SUBMITTED', 'PENDING', 'UNKNOWN']) {
        final mock = MockDirectUpiGateway(
          intentResult: {'status': rawStatus},
        );
        DirectUpiService.gateway = mock;

        final res = await DirectUpiService.initiateAndPay(
          invoiceId: 'inv-uuid-2',
          selectedApp: const InstalledUpiApp(name: 'PhonePe', packageName: 'com.phonepe.app'),
        );

        expect(res.isSettled, isFalse);
        expect(res.backendStatus, 'PENDING_VERIFICATION');
        expect(res.canRetry, isFalse);
        expect(res.outcome.userMessage, DirectUpiService.msgWaitingConfirmation);
      }
    });

    test('FAILURE, NETWORK_ERROR, and CANCELLED allow safe retry with exact messages', () async {
      final failMock = MockDirectUpiGateway(intentResult: {'status': 'FAILURE', 'responseCode': 'U16'});
      DirectUpiService.gateway = failMock;
      final failRes = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-3',
        selectedApp: const InstalledUpiApp(name: 'Paytm', packageName: 'net.one97.paytm'),
      );
      expect(failRes.backendStatus, 'FAILED');
      expect(failRes.canRetry, isTrue);
      expect(failRes.outcome.userMessage, DirectUpiService.msgNotCompleted);

      final netMock = MockDirectUpiGateway(intentResult: {'status': 'NETWORK_ERROR'});
      DirectUpiService.gateway = netMock;
      final netRes = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-3',
        selectedApp: const InstalledUpiApp(name: 'Paytm', packageName: 'net.one97.paytm'),
      );
      expect(netRes.canRetry, isTrue);

      final cancelMock = MockDirectUpiGateway(intentResult: {'status': 'CANCELLED'});
      DirectUpiService.gateway = cancelMock;
      final cancelRes = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-3',
        selectedApp: const InstalledUpiApp(name: 'BHIM', packageName: 'in.org.npci.upiapp'),
      );
      expect(cancelRes.backendStatus, 'CANCELLED');
      expect(cancelRes.canRetry, isTrue);
      expect(cancelRes.outcome.userMessage, DirectUpiService.msgCancelled);
    });

    test('UPI limit exceeded (Z9) and PhonePe security restrictions return bank guidance without bypass', () async {
      final limitMock = MockDirectUpiGateway(
        intentResult: {
          'status': 'FAILURE',
          'responseCode': 'Z9',
          'rawResponse': 'Status=FAILURE&responseCode=Z9&message=UPI limit exceeded',
        },
      );
      DirectUpiService.gateway = limitMock;
      final limitRes = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-4',
        selectedApp: const InstalledUpiApp(
          name: 'Google Pay',
          packageName: 'com.google.android.apps.nbu.paisa.user',
        ),
      );
      expect(limitRes.outcome.isLimitOrSecurityRestricted, isTrue);
      expect(limitRes.outcome.errorCategory, DirectUpiErrorCategory.bankLimitRejection);
      expect(limitRes.outcome.userMessage, DirectUpiService.msgBankRestricted);

      final secMock = MockDirectUpiGateway(
        intentResult: {
          'status': 'FAILURE',
          'message': 'Declined for security reasons by PhonePe',
        },
      );
      DirectUpiService.gateway = secMock;
      final secRes = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-4',
        selectedApp: const InstalledUpiApp(name: 'PhonePe', packageName: 'com.phonepe.app'),
      );
      expect(secRes.outcome.isLimitOrSecurityRestricted, isTrue);
      expect(secRes.outcome.errorCategory, DirectUpiErrorCategory.securityRejection);
      expect(secRes.outcome.userMessage, DirectUpiService.msgBankRestricted);
    });

    test('APP_NOT_INSTALLED cancels stale initiation and permits choosing another app', () async {
      final missingMock = MockDirectUpiGateway(intentResult: {'status': 'APP_NOT_INSTALLED'});
      DirectUpiService.gateway = missingMock;

      final res = await DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-5',
        selectedApp: const InstalledUpiApp(name: 'Paytm', packageName: 'net.one97.paytm'),
      );
      expect(missingMock.cancelCallCount, 1);
      expect(missingMock.responseSyncCount, 0);
      expect(res.canRetry, isTrue);
      expect(res.outcome.userMessage, DirectUpiService.msgAppNotInstalled);
    });

    test('Duplicate tap prevention blocks concurrent initiateAndPay calls', () async {
      final completer = Completer<Map<String, dynamic>>();
      final mock = MockDirectUpiGateway(pendingLaunchCompleter: completer);
      DirectUpiService.gateway = mock;

      final firstFuture = DirectUpiService.initiateAndPay(
        invoiceId: 'inv-uuid-6',
        selectedApp: const InstalledUpiApp(
          name: 'Google Pay',
          packageName: 'com.google.android.apps.nbu.paisa.user',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        () => DirectUpiService.initiateAndPay(
          invoiceId: 'inv-uuid-6',
          selectedApp: const InstalledUpiApp(
            name: 'Google Pay',
            packageName: 'com.google.android.apps.nbu.paisa.user',
          ),
        ),
        throwsStateError,
      );

      completer.complete({'status': 'SUBMITTED'});
      final result = await firstFuture;
      expect(result.backendStatus, 'PENDING_VERIFICATION');
    });
  });

  group('Direct UPI UI Widget Scenarios', () {
    testWidgets('RentPaymentScreen dynamically renders installed UPI apps and Pay using UPI launches selected app', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mock = MockDirectUpiGateway();
      DirectUpiService.gateway = mock;

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-WIDGET-001',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Installed UPI Apps'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('Paytm'), findsOneWidget);
      expect(find.text('BHIM'), findsOneWidget);
      expect(find.text('Pay using UPI'), findsOneWidget);

      await tester.tap(find.text('Paytm'));
      await tester.pump();
      await tester.tap(find.text('Pay using UPI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(mock.launchedPackage, 'net.one97.paytm');
      expect(find.text('Payment Pending Verification'), findsOneWidget);
      expect(find.text('Retry Payment'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('RentPaymentScreen shows empty fallback state when no UPI apps are installed', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      DirectUpiService.gateway = MockDirectUpiGateway(appsToReturn: const []);

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-WIDGET-EMPTY',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No UPI apps installed on this device. Install Google Pay, PhonePe, Paytm, or BHIM to pay via Direct UPI.'),
        findsOneWidget,
      );
      expect(find.text('Pay using UPI'), findsNothing);
    });

    testWidgets('PaymentStatusScreen shows exact verified & failed messages and enables retry only on failure', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaymentStatusScreen(
            paymentData: {
              'invoiceId': 'INV-FAIL-1',
              'amount': 8000,
              'paymentApp': 'PhonePe',
              'txnRef': 'TXNFAIL01',
              'initialState': 'failed',
              'statusMessage': DirectUpiService.msgBankRestricted,
              'autoPoll': false,
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Payment Failed'), findsOneWidget);
      expect(find.text(DirectUpiService.msgBankRestricted), findsOneWidget);
      expect(find.text('Retry Payment'), findsOneWidget);
    });
  });
}

