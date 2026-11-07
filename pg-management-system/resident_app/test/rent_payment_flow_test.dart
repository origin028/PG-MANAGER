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
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('Pay using PhonePe'), findsOneWidget);
    });

    testWidgets('RentPaymentScreen opens payment options modal with PhonePe and Google Pay when autoOpen is true', (WidgetTester tester) async {
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
      expect(find.textContaining('Select PhonePe or Google Pay'), findsOneWidget);
      expect(find.text('Opens Google Pay app directly to pay'), findsOneWidget);
      expect(find.text('Opens PhonePe app directly to pay'), findsOneWidget);

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

  group('Gateway-Free UPI Payment Methods Tests', () {
    testWidgets('RentPaymentScreen renders both gateway-free options on screen and in modal', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-FREE-1',
              'month': 'November 2026',
              'amount': 8000,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      // Check method 1 tile
      expect(find.text('Pay using Google Pay'), findsOneWidget);
      expect(find.text('Auto-copies UPI ID & opens Google Pay for reliable transfer'), findsOneWidget);

      // Check method 2 tile
      expect(find.text('Dynamic UPI QR Code'), findsOneWidget);
      expect(find.text('Scan to pay with another phone or from gallery'), findsOneWidget);

      // Open modal
      await tester.tap(find.text('Pay ₹ 8000 Now'));
      await tester.pumpAndSettle();

      // Modal options
      expect(find.text('Payment Options'), findsOneWidget);
      expect(find.text('Auto-copies UPI ID & opens Google Pay for reliable transfer'), findsNWidgets(2));
      expect(find.text('Scan to pay with another phone or from gallery'), findsNWidgets(2));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Method 1: Pay using Google Pay copies VPA and displays complete instructions & buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-FREE-1',
              'month': 'November 2026',
              'amount': 1.0,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      // Tap "Pay using Google Pay"
      await tester.tap(find.text('Pay using Google Pay').first);
      await tester.pumpAndSettle();

      // Verify bottom sheet contents
      expect(find.text('UPI ID auto-copied to clipboard'), findsOneWidget);
      expect(find.text('masisokatali90900@okaxis'), findsWidgets);
      expect(find.text("Saukatali Masi"), findsWidgets);
      expect(find.text('₹ 1.00'), findsWidgets);

      // Verify step instructions
      expect(find.text('How to complete your payment:'), findsOneWidget);
      expect(find.text('Open Google Pay App'), findsOneWidget);
      expect(find.text('I Have Paid / Check Status'), findsOneWidget);

      // Verify important disclaimer is present
      expect(find.textContaining('Payment details are not automatically prefilled in Google Pay'), findsOneWidget);

      // Verify clipboard has VPA
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clip?.text, 'masisokatali90900@okaxis');

      // Tap Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('Method 2: Dynamic UPI QR Code renders QrImageView, instructions, and save/share actions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-FREE-QR',
              'month': 'November 2026',
              'amount': 1.0,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pump();

      // Tap "Dynamic UPI QR Code"
      await tester.tap(find.text('Dynamic UPI QR Code').first);
      await tester.pumpAndSettle();

      // Verify dynamic QR modal is open
      expect(find.text('Scan with any UPI app to pay ₹1.00'), findsOneWidget);
      expect(find.text('masisokatali90900@okaxis'), findsWidgets);
      expect(find.text("Saukatali Masi"), findsWidgets);
      expect(find.text('INV-TEST-FREE-QR'), findsWidgets);
      expect(find.text('₹ 1.00'), findsWidgets);

      // Verify scanner instructions
      expect(find.text('How to scan this QR Code:'), findsOneWidget);
      expect(find.textContaining('A phone cannot scan a QR code displayed directly on its own screen'), findsOneWidget);

      // Verify actions
      expect(find.text('Save QR Link'), findsOneWidget);
      expect(find.text('Share Details'), findsOneWidget);
      expect(find.text('I Have Transferred / Confirm Payment'), findsOneWidget);

      // Test Save QR Link copies valid URI
      await tester.tap(find.text('Save QR Link'));
      await tester.pumpAndSettle();
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipData?.text, startsWith('upi://pay?'));
      expect(clipData?.text, contains('pa=masisokatali90900%40okaxis'));
      expect(clipData?.text, contains('am=1.00'));
      expect(clipData?.text, contains('cu=INR'));

      // Test Share Details copies summary
      await tester.tap(find.text('Share Details'));
      await tester.pumpAndSettle();
      final shareClip = await Clipboard.getData(Clipboard.kTextPlain);
      expect(shareClip?.text, contains('INV-TEST-FREE-QR'));
      expect(shareClip?.text, contains("Saukatali Masi"));
      expect(shareClip?.text, contains('₹1.00'));

      // Tap Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('Method 1 from modal opens Google Pay instruction dialog seamlessly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-MODAL-1',
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

      // In open modal, tap "Pay using Google Pay"
      await tester.tap(find.text('Pay using Google Pay').last);
      await tester.pumpAndSettle();

      // Should open the instruction bottom sheet
      expect(find.text('Open Google Pay App'), findsOneWidget);
      expect(find.text('UPI ID auto-copied to clipboard'), findsOneWidget);

      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
    });

    testWidgets('Method 2 from modal opens Dynamic QR bottom sheet seamlessly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-MODAL-2',
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

      // In open modal, tap "Dynamic UPI QR Code"
      await tester.tap(find.text('Dynamic UPI QR Code').last);
      await tester.pumpAndSettle();

      // Should open the Dynamic QR bottom sheet
      expect(find.text('Dynamic UPI QR Code'), findsWidgets);
      expect(find.text('Save QR Link'), findsOneWidget);
      expect(find.text('Share Details'), findsOneWidget);

      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
    });
  });

  group('Dedicated PhonePe Direct Integration Tests', () {
    test('RentPaymentScreen.phonePePackage targets com.phonepe.app strictly', () {
      expect(RentPaymentScreen.phonePePackage, 'com.phonepe.app');
    });

    test('buildPhonePeIntentUri generates valid Android Intent targeting com.phonepe.app with ₹1.00', () {
      final intentUri = RentPaymentScreen.buildPhonePeIntentUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: "Saukatali Masi",
        amount: 1.0,
        currency: 'INR',
        transactionNote: "Rent Payment INV-2026-TEST - Saukatali Masi",
        transactionRef: 'UPI-20261106-PHONEPE1',
      );

      final uriString = intentUri.toString();
      expect(uriString, startsWith('intent://pay?'));
      expect(uriString, contains('pa=masisokatali90900%40okaxis'));
      expect(uriString, contains('pn=Saukatali%20Masi'));
      expect(uriString, contains('am=1.00'));
      expect(uriString, contains('cu=INR'));
      expect(uriString, contains('tr=UPI-20261106-PHONEPE1'));
      expect(uriString, endsWith('#Intent;scheme=upi;package=com.phonepe.app;end'));
    });

    test('buildPhonePeIntentUri generates valid Android Intent targeting com.phonepe.app with ₹8000.00 and merchantCode', () {
      final intentUri = RentPaymentScreen.buildPhonePeIntentUri(
        payeeVpa: 'masisokatali90900@okaxis',
        payeeName: "Saukatali Masi",
        amount: 8000.0,
        currency: 'INR',
        transactionNote: "Rent Payment INV-2026-010 - Saukatali Masi",
        transactionRef: 'UPI-20261106-PHONEPE8000',
        merchantCode: '6513',
      );

      final uriString = intentUri.toString();
      expect(uriString, startsWith('intent://pay?'));
      expect(uriString, contains('am=8000.00'));
      expect(uriString, contains('mc=6513'));
      expect(uriString, endsWith('#Intent;scheme=upi;package=com.phonepe.app;end'));
    });

    testWidgets('Pay using PhonePe tile renders with subtitle specifying com.phonepe.app', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-PHONEPE-UI',
              'month': 'November 2026',
              'amount': 1.0,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pay using PhonePe'), findsOneWidget);
      expect(find.text('Direct UPI payment via PhonePe (com.phonepe.app)'), findsOneWidget);
    });

    testWidgets('Modal contains Pay using PhonePe with direct intent description', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-PHONEPE-MODAL',
              'month': 'November 2026',
              'amount': 1.0,
              'date': '05 Nov 2026',
              'status': 'Pending',
              'autoOpen': true,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In autoOpen mode, Pay using PhonePe appears on both the background page and the modal sheet
      expect(find.text('Pay using PhonePe'), findsNWidgets(2));
      expect(find.text('Opens PhonePe app directly to pay'), findsOneWidget);
    });

    testWidgets('Tapping Pay using PhonePe invokes native channel and sets PENDING_VERIFICATION', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? invokedMethod;
      Map<dynamic, dynamic>? invokedArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.originpg.resident/native_upi'),
        (MethodCall call) async {
          invokedMethod = call.method;
          invokedArgs = call.arguments as Map<dynamic, dynamic>?;
          return {'status': 'SUCCESS', 'method': 'EXPLICIT_UPI_INTENT'};
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-PHONEPE-TAP',
              'month': 'November 2026',
              'amount': 1.0,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay using PhonePe').first);
      await tester.pumpAndSettle();

      expect(invokedMethod, 'launchPhonePeDirect');
      expect(invokedArgs?['package'], 'com.phonepe.app');
      expect(invokedArgs?['payeeVpa'], 'masisokatali90900@okaxis');
      expect(invokedArgs?['payeeName'], "Saukatali Masi");
      expect(invokedArgs?['amount'], '1.00');

      // Verify payment verification service saved state in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pg_payment_tx_INV-TEST-PHONEPE-TAP');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['state'], 'pendingVerification');
      expect(json['paymentApp'], 'PhonePe');
    });

    testWidgets('When PhonePe cannot be resolved, dialog displays without opening generic chooser', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.originpg.resident/native_upi'),
        (MethodCall call) async {
          return {'status': 'ACTIVITY_NOT_RESOLVED', 'message': 'No activity found'};
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: RentPaymentScreen(
            invoiceData: {
              'id': 'INV-TEST-PHONEPE-UNAVAIL',
              'month': 'November 2026',
              'amount': 1.0,
              'date': '05 Nov 2026',
              'status': 'Pending',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay using PhonePe').first);
      await tester.pumpAndSettle();

      // Should display PhonePe Not Available dialog
      expect(find.text('PhonePe Not Available'), findsOneWidget);
      expect(find.textContaining('The PhonePe application (com.phonepe.app) could not be opened'), findsOneWidget);
      expect(find.text('masisokatali90900@okaxis'), findsWidgets);
      expect(find.text('Use Other UPI App'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
