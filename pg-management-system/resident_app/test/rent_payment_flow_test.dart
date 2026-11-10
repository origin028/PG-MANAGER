import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/services/payment_verification_service.dart';
import 'package:resident_app/features/payments/rent_payment_screen.dart';
import 'package:resident_app/features/payments/payment_status_screen.dart';
import 'package:resident_app/features/payments/receipt_screen.dart';
import 'package:resident_app/features/notices/notices_screen.dart';

String? mockClipboardContent;

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockClipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map?;
          mockClipboardContent = args?['text'] as String?;
          return null;
        } else if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': mockClipboardContent};
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.originpg.resident/native_upi'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'launchPhonePeDirect') {
          return <String, dynamic>{'status': 'SUCCESS', 'method': 'EXPLICIT_UPI_INTENT'};
        } else if (methodCall.method == 'isPackageInstalled') {
          return true;
        }
        return null;
      },
    );
    AppData.currentResident = {
      ...AppData.currentResident,
      'rent_status': 'Pending',
      'rent': 8000,
    };
  });

  group('PaymentVerificationService Tests', () {
    test('initiatePayment stores and returns pendingVerification result', () async {
      final result = await PaymentVerificationService.initiatePayment(
        invoiceId: 'INV-TEST-001',
        amount: 8500,
        paymentApp: 'Google Pay',
        txnRef: 'TXN-REF-12345',
      );

      expect(result.state, PaymentVerificationState.pendingVerification);
      expect(result.invoiceId, 'INV-TEST-001');
      expect(result.amount, 8500);
      expect(result.paymentApp, 'Google Pay');
      expect(result.transactionRef, 'TXN-REF-12345');
    });

    test('verify payee constants match verified payee details', () {
      expect(PaymentVerificationService.verifiedPayeeUpiId, 'masisokatali90900@okaxis');
      expect(PaymentVerificationService.verifiedPayeeName, "Saukatali Masi");
      expect(PaymentVerificationService.verifiedCurrency, 'INR');
    });

    test('verifyWithBackend keeps real UPI payments in pendingVerification without auto-settlement', () async {
      final result = await PaymentVerificationService.verifyWithBackend(
        invoiceId: 'INV-TEST-002',
        txnRef: 'TXN-REF-99999',
        paymentApp: 'Google Pay',
        amount: 8000,
      );

      // Strict security rule: returning from UPI app does NOT mark as paid
      expect(result.state, PaymentVerificationState.pendingVerification);
    });

    test('verifyWithBackend returns successful verification with receipt data for Demo Pay or forceSuccess', () async {
      final demoResult = await PaymentVerificationService.verifyWithBackend(
        invoiceId: 'INV-TEST-002-DEMO',
        txnRef: 'TXN-REF-DEMO1',
        paymentApp: 'Demo Pay',
        amount: 8000,
      );

      expect(demoResult.state, PaymentVerificationState.successful);
      expect(demoResult.bankApprovalCode, isNotNull);
      expect(demoResult.bankApprovalCode, contains('BANK-AUTH-'));
      expect(demoResult.receiptData, isNotNull);
      expect(demoResult.receiptData!['status'], 'Verified & Settled');

      final forceResult = await PaymentVerificationService.verifyWithBackend(
        invoiceId: 'INV-TEST-002-FORCE',
        txnRef: 'TXN-REF-FORCE1',
        paymentApp: 'Google Pay',
        amount: 8000,
        forceSuccess: true,
      );
      expect(forceResult.state, PaymentVerificationState.successful);
    });

    test('simulateBankSettlement marks invoice as settled with verified receipt', () async {
      final result = await PaymentVerificationService.simulateBankSettlement(
        invoiceId: 'INV-TEST-SETTLE',
        txnRef: 'TXN-REF-SETTLE1',
        paymentApp: 'Google Pay',
        amount: 8000,
      );

      expect(result.state, PaymentVerificationState.successful);
      expect(result.receiptData, isNotNull);
      expect(result.receiptData!['status'], 'Verified & Settled');
      expect(result.receiptData!['propertyName'], "Saukatali Masi");
    });

    test('verifyWithBackend supports forceFail and forceCancel states', () async {
      final failResult = await PaymentVerificationService.verifyWithBackend(
        invoiceId: 'INV-TEST-003',
        txnRef: 'TXN-FAIL-1',
        paymentApp: 'Google Pay',
        amount: 8000,
        forceFail: true,
      );
      expect(failResult.state, PaymentVerificationState.failed);

      final cancelResult = await PaymentVerificationService.verifyWithBackend(
        invoiceId: 'INV-TEST-004',
        txnRef: 'TXN-CANCEL-1',
        paymentApp: 'PhonePe',
        amount: 8000,
        forceCancel: true,
      );
      expect(cancelResult.state, PaymentVerificationState.cancelled);
    });
  });

  group('Rent Payment UI Flow Widget Tests', () {
    testWidgets('RentPaymentScreen displays rent amount, invoice, payee, and UPI options', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-2026-010',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Rent Payment'), findsOneWidget);
      expect(find.text('TOTAL RENT DUE'), findsOneWidget);
      expect(find.text('₹ 8000'), findsOneWidget);
      expect(find.text('INV-2026-010'), findsOneWidget);
      expect(find.text('05 Nov 2026'), findsOneWidget);
      expect(find.textContaining('PG Owner'), findsOneWidget);
      expect(find.text('Select Payment Method'), findsOneWidget);
      expect(find.text('Google Pay (G Pay)'), findsOneWidget);
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('PayPal'), findsOneWidget);
      expect(find.text('Credit Card / Debit Card'), findsOneWidget);
    });

    testWidgets('RentPaymentScreen opens payment options modal with 4 clean payment methods when autoOpen is true', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-2026-010',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
              'autoOpen': true,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Modal should be open showing Payment Options
      expect(find.text('Payment Options'), findsOneWidget);
      expect(find.textContaining('Choose from Google Pay, PhonePe, PayPal, or Credit Card'), findsOneWidget);
      expect(find.text('Google Pay (G Pay)'), findsNWidgets(2));
      expect(find.text('PhonePe'), findsNWidgets(2));
      expect(find.text('PayPal'), findsNWidgets(2));
      expect(find.text('Credit Card / Debit Card'), findsNWidgets(2));

      // Cancel button closes modal
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Options'), findsNothing);
    });

    testWidgets('ReceiptScreen displays complete verified payment breakdown and actions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final receiptData = {
        'receiptNumber': 'REC-2026-11-9988',
        'invoiceId': 'INV-2026-010',
        'amount': 8000,
        'paymentApp': 'Google Pay',
        'transactionRef': 'UPI-20261029-778899',
        'bankApprovalCode': 'BANK-AUTH-55443',
        'paidAt': '2026-10-29T10:30:00.000Z',
        'residentName': 'Akshay B',
        'roomNumber': '101',
        'propertyName': 'BNR Luxury PG',
        'status': 'Verified & Settled',
      };

      await tester.pumpWidget(MaterialApp(home: ReceiptScreen(receiptData: receiptData)));
      await tester.pump();

      expect(find.text('Rent Receipt'), findsOneWidget);
      expect(find.text('BNR Luxury PG'), findsOneWidget);
      expect(find.text('VERIFIED & PAID'), findsOneWidget);
      expect(find.text('REC-2026-11-9988'), findsOneWidget);
      expect(find.text('INV-2026-010'), findsOneWidget);
      expect(find.text('₹ 8000'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('Akshay B'), findsOneWidget);
      expect(find.text('Room 101'), findsOneWidget);
      expect(find.text('BANK-AUTH-55443'), findsOneWidget);
      expect(find.text('Download Receipt PDF / Summary'), findsOneWidget);
    });

    testWidgets('NoticesScreen renders general announcements and no rent reminder card', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: NoticesScreen()));
      await tester.pump();

      expect(find.text('Notices & Circulars'), findsOneWidget);
      expect(find.text('Water supply maintenance'), findsOneWidget);
      expect(find.text('High-Speed Wi-Fi Upgrade'), findsOneWidget);
      expect(find.text('Monthly Rent Due Reminder'), findsNothing);
      expect(find.text('RENT DUE AMOUNT'), findsNothing);
    });

    testWidgets('PaymentStatusScreen renders pending verification and cancelled states', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PaymentStatusScreen(
            paymentData: {
              'invoiceId': 'INV-2026-010',
              'amount': 8000,
              'paymentApp': 'Google Pay',
              'txnRef': 'UPI-20261029-123456',
              'autoPoll': false,
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Payment Status'), findsOneWidget);
      expect(find.text('Payment Pending Verification'), findsOneWidget);
      expect(find.text('INV-2026-010'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('Refresh Status'), findsOneWidget);
      expect(find.text('Simulate Cancelled'), findsOneWidget);
      expect(find.text('Simulate Failed'), findsOneWidget);

      // Tap Simulate Cancelled
      await tester.tap(find.text('Simulate Cancelled'));
      await tester.pump();

      expect(find.text('Payment Cancelled'), findsOneWidget);
      expect(find.text('Choose Another Payment Option'), findsOneWidget);
    });
  });

  group('UPI Intent Generation & Payable Amount Calculation Tests', () {
    test('calculatePayableAmount correctly extracts ₹1.00 test amount for various formats', () {
      expect(RentPaymentScreen.calculatePayableAmount({'amount': 1.0}), 1.0);
      expect(RentPaymentScreen.calculatePayableAmount({'amount': 1}), 1.0);
      expect(RentPaymentScreen.calculatePayableAmount({'amount': '1.00'}), 1.0);
      expect(RentPaymentScreen.calculatePayableAmount({'amount': '1'}), 1.0);
      // Remaining / balance amount takes precedence over total invoice amount
      expect(RentPaymentScreen.calculatePayableAmount({'balance_amount': 1.0, 'amount': 8000.0}), 1.0);
      expect(RentPaymentScreen.calculatePayableAmount({'remaining_amount': '1.00', 'amount': '8000'}), 1.0);
    });

    test('calculatePayableAmount correctly extracts ₹8000.00 regular amount and handles defaults', () {
      expect(RentPaymentScreen.calculatePayableAmount({'amount': 8000.0}), 8000.0);
      expect(RentPaymentScreen.calculatePayableAmount({'amount': 8000}), 8000.0);
      expect(RentPaymentScreen.calculatePayableAmount({'amount': '8000.00'}), 8000.0);
      expect(RentPaymentScreen.calculatePayableAmount(null), 8000.0);
      expect(RentPaymentScreen.calculatePayableAmount({}), 8000.0);
    });

    test('buildUpiUri constructs compliant NPCI URI for ₹1.00 test invoice with verified parameters', () {
      final uri = RentPaymentScreen.buildUpiUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: "Saukatali Masi",
        amount: 1.0,
        currency: 'INR',
        transactionNote: "Rent Payment INV-2026-TEST - Saukatali Masi",
        transactionRef: 'UPI-20261105-998877',
      );

      // Verify Scheme & Host
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');

      // Verify Query Parameters
      expect(uri.queryParameters['pa'], 'masisokatali90900@okaxis');
      expect(uri.queryParameters['pn'], "Saukatali Masi");
      expect(uri.queryParameters['am'], '1.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tn'], "Rent Payment INV-2026-TEST - Saukatali Masi");
      expect(uri.queryParameters['tr'], 'UPI-20261105-998877');

      // Verify absence of non-standard package query pollution
      expect(uri.queryParameters.containsKey('package'), isFalse, reason: 'package must not pollute URI query');

      // Verify URI string formatting
      final uriString = uri.toString();
      expect(uriString, startsWith('upi://pay?'));
      expect(uriString, contains('pa=masisokatali90900%40okaxis'));
      expect(uriString, contains('am=1.00'));
      expect(uriString, contains('cu=INR'));
      expect(uriString, contains('tr=UPI-20261105-998877'));
      expect(uriString, contains('tn=Rent%20Payment%20INV-2026-TEST%20-%20Saukatali%20Masi'));
      expect(uriString.contains('Rent+Payment'), isFalse, reason: 'Must not use literal + signs for spaces in note');
      expect(uriString.startsWith('tez://'), isFalse, reason: 'Must not use tez:// proprietary scheme');
    });

    test('buildUpiUri constructs compliant NPCI URI for ₹8000.00 regular invoice', () {
      final uri = RentPaymentScreen.buildUpiUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: "Saukatali Masi",
        amount: 8000.0,
        currency: 'INR',
        transactionNote: "Rent Payment INV-2026-010 - Saukatali Masi",
        transactionRef: 'UPI-20261105-887766',
      );

      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'masisokatali90900@okaxis');
      expect(uri.queryParameters['pn'], "Saukatali Masi");
      expect(uri.queryParameters['am'], '8000.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tn'], "Rent Payment INV-2026-010 - Saukatali Masi");
      expect(uri.queryParameters['tr'], 'UPI-20261105-887766');
    });

    test('buildUpiUri trims whitespace safely and handles optional merchant code', () {
      final uri = RentPaymentScreen.buildUpiUri(
        payeeVpa: '  masisokatali90900@okaxis  ',
        payeeName: "  Saukatali Masi  ",
        amount: 1.00,
        currency: ' INR ',
        transactionNote: '  Rent Payment Test  ',
        transactionRef: '  UPI-REF-001  ',
        merchantCode: ' 6513 ',
      );

      expect(uri.queryParameters['pa'], 'masisokatali90900@okaxis');
      expect(uri.queryParameters['pn'], "Saukatali Masi");
      expect(uri.queryParameters['am'], '1.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tn'], 'Rent Payment Test');
      expect(uri.queryParameters['tr'], 'UPI-REF-001');
      expect(uri.queryParameters['mc'], '6513');
    });

    test('buildUpiUri handles bank merchant VPA with real MCC 6513 for Direct BoB Intent', () {
      final uri = RentPaymentScreen.buildUpiUri(
        payeeVpa: 'smartgrouppg@barodampay',
        payeeName: "SMART GROUP PG'S",
        amount: 8000.00,
        currency: 'INR',
        transactionNote: 'Rent payment - SMART GROUP PGS',
        transactionRef: 'TXN-BOB-20261105-001',
        merchantCode: '6513',
      );

      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'smartgrouppg@barodampay');
      expect(uri.queryParameters['pn'], "SMART GROUP PG'S");
      expect(uri.queryParameters['am'], '8000.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tr'], 'TXN-BOB-20261105-001');
      expect(uri.queryParameters['mc'], '6513');

      // URI formatting
      final uriStr = uri.toString();
      expect(uriStr, contains('pa=smartgrouppg%40barodampay'));
      expect(uriStr, contains('am=8000.00'));
      expect(uriStr, contains('mc=6513'));
      expect(uriStr, contains('tr=TXN-BOB-20261105-001'));
    });

    test('formatTransactionNote formats full UUID into readable 8-character prefix format', () {
      final note = RentPaymentScreen.formatTransactionNote(
        invoiceId: '08bd684a-57b1-4c67-b50a-9d044f51e0ff',
        payeeName: 'Saukatali Masi',
      );
      expect(note, 'Rent Payment - 08bd684a - Saukatali Masi');
    });

    test('formatTransactionNote formats INV-prefixed invoice into readable text', () {
      final note = RentPaymentScreen.formatTransactionNote(
        invoiceId: 'INV-2026-TEST',
        payeeName: 'Saukatali Masi',
      );
      expect(note, 'Rent Payment - INV-2026-TEST - Saukatali Masi');
    });

    test('buildUpiUri encodes tn with UTF-8 percent-encoding (%20) ensuring receiving UPI apps decode readable text', () {
      final note = RentPaymentScreen.formatTransactionNote(
        invoiceId: '08bd684a-57b1-4c67-b50a-9d044f51e0ff',
        payeeName: 'Saukatali Masi',
      );
      final uri = RentPaymentScreen.buildUpiUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: 'Saukatali Masi',
        amount: 1.00,
        transactionNote: note,
        transactionRef: 'UPI-20261106-08BD684A',
      );

      final uriString = uri.toString();
      // Must contain %20 URL encoding and no '+' literal spaces
      expect(uriString, contains('tn=Rent%20Payment%20-%2008bd684a%20-%20Saukatali%20Masi'));
      expect(uriString.contains('+'), isFalse, reason: 'No query parameter should contain form-urlencoded + for spaces');

      // Receiving UPI app decoding simulation (standard RFC 3986 percent decoding)
      expect(uri.queryParameters['tn'], 'Rent Payment - 08bd684a - Saukatali Masi');
      expect(Uri.decodeComponent(uri.queryParameters['tn']!), 'Rent Payment - 08bd684a - Saukatali Masi');
    });

    test('buildUpiUri with ₹1 TEST invoice produces valid URI with readable decoded note', () {
      final note = RentPaymentScreen.formatTransactionNote(
        invoiceId: 'INV-2026-TEST',
        payeeName: 'Saukatali Masi',
      );
      final uri = RentPaymentScreen.buildUpiUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: 'Saukatali Masi',
        amount: 1.00,
        currency: 'INR',
        transactionNote: note,
        transactionRef: 'UPI-TEST-1INR',
      );

      expect(uri.queryParameters['am'], '1.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['pa'], 'masisokatali90900@okaxis');
      expect(uri.queryParameters['pn'], 'Saukatali Masi');
      expect(uri.queryParameters['tn'], 'Rent Payment - INV-2026-TEST - Saukatali Masi');

      final rawUri = uri.toString();
      expect(rawUri, contains('tn=Rent%20Payment%20-%20INV-2026-TEST%20-%20Saukatali%20Masi'));
      expect(rawUri.contains('+'), isFalse);
    });
  });

  group('Four Primary Payment Methods Tests (GPay, PhonePe, PayPal, Credit Card)', () {
    testWidgets('RentPaymentScreen renders 4 primary options on screen and in modal', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-4METHODS',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      // Verify all 4 primary options exist
      expect(find.text('Google Pay (G Pay)'), findsOneWidget);
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('PayPal'), findsOneWidget);
      expect(find.text('Credit Card / Debit Card'), findsOneWidget);

      // Open bottom sheet modal via 'Pay ₹ 8000 Now'
      await tester.tap(find.text('Pay ₹ 8000 Now'));
      await tester.pumpAndSettle();

      // Modal options should also list all 4
      expect(find.text('Payment Options'), findsOneWidget);
      expect(find.text('Google Pay (G Pay)'), findsNWidgets(2));
      expect(find.text('PhonePe'), findsNWidgets(2));
      expect(find.text('PayPal'), findsNWidgets(2));
      expect(find.text('Credit Card / Debit Card'), findsNWidgets(2));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping Google Pay opens redirect modal with QR, app open button, and instant confirm', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-GPAY',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Google Pay (G Pay)'));
      await tester.pumpAndSettle();

      expect(find.text('Redirecting to Google Pay app...'), findsOneWidget);
      expect(find.text('Open Google Pay App'), findsOneWidget);
      expect(find.text('I Have Paid via Google Pay (Confirm)'), findsOneWidget);

      // Confirm payment instant settlement
      await tester.tap(find.text('I Have Paid via Google Pay (Confirm)'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pg_payment_tx_INV-TEST-GPAY');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['state'], 'successful');
      expect(json['paymentApp'], 'Google Pay');
    });

    testWidgets('Tapping PhonePe opens redirect modal with QR, app open button, and instant confirm', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-PHONEPE',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('PhonePe'));
      await tester.pumpAndSettle();

      expect(find.text('Redirecting to PhonePe app...'), findsOneWidget);
      expect(find.text('Open PhonePe App'), findsOneWidget);
      expect(find.text('I Have Paid via PhonePe (Confirm)'), findsOneWidget);

      await tester.tap(find.text('I Have Paid via PhonePe (Confirm)'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pg_payment_tx_INV-TEST-PHONEPE');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['state'], 'successful');
      expect(json['paymentApp'], 'PhonePe');
    });

    testWidgets('Tapping PayPal opens PayPal checkout modal and settles successfully', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-PAYPAL',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('PayPal'));
      await tester.pumpAndSettle();

      expect(find.text('PayPal Checkout'), findsOneWidget);
      expect(find.text('Redirecting to PayPal secure session...'), findsOneWidget);
      expect(find.text('Pay ₹8000 with PayPal'), findsOneWidget);

      await tester.tap(find.text('Pay ₹8000 with PayPal'));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pg_payment_tx_INV-TEST-PAYPAL');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['state'], 'successful');
      expect(json['paymentApp'], 'PayPal');
    });

    testWidgets('Tapping Credit Card opens Credit Card checkout modal and settles successfully', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-CC',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Credit Card / Debit Card'));
      await tester.pumpAndSettle();

      expect(find.text('Credit Card / Debit Card'), findsNWidgets(2));
      expect(find.text('Pay ₹8000 Securely'), findsOneWidget);

      await tester.tap(find.text('Pay ₹8000 Securely'));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pg_payment_tx_INV-TEST-CC');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['state'], 'successful');
      expect(json['paymentApp'], 'Credit Card');
    });
  });
}
