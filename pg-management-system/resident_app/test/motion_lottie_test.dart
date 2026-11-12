import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resident_app/core/router/app_router.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/core/widgets/motion_wrappers.dart';
import 'package:resident_app/features/auth/login_screen.dart';
import 'package:resident_app/features/complaints/complaints_screen.dart';
import 'package:resident_app/features/notices/notices_screen.dart';
import 'package:resident_app/features/payments/payment_status_screen.dart';
import 'package:resident_app/features/payments/receipt_screen.dart';
import 'package:resident_app/features/payments/rent_payment_screen.dart';
import 'package:resident_app/features/profile/rent_deposit_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Lottie asset validation', () {
    test('payment_success.json and empty_notices.json are valid bounded vector Lotties', () async {
      for (final assetPath in [
        'assets/animations/payment_success.json',
        'assets/animations/empty_notices.json',
      ]) {
        final raw = await rootBundle.loadString(assetPath);
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['fr'], 30);
        expect((decoded['op'] as num) > 0, isTrue);
        expect((decoded['layers'] as List).isNotEmpty, isTrue);
      }
    });
  });

  group('Motion primitives & reduced motion support', () {
    testWidgets('MotionEntrance settles cleanly and bypasses transitions when disableAnimations is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MotionEntrance(
              delay: Duration(milliseconds: 80),
              child: Text('Entrance Target'),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(MotionEntrance),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.text('Entrance Target'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: MotionEntrance(
                delay: Duration(milliseconds: 80),
                child: Text('Reduced Motion Target'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Reduced Motion Target'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MotionEntrance),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('TactilePress preserves child tap callback and responds smoothly to pointer events',
        (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TactilePress(
                child: ElevatedButton(
                  onPressed: () => tapped = true,
                  child: const Text('Tap Me'),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.text('Tap Me')));
      await tester.pump(const Duration(milliseconds: 120));
      var scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 0.975);

      await gesture.up();
      await tester.pumpAndSettle();
      scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0);
      expect(tapped, isTrue);
    });
  });

  group('Lottie gating & confirmation safety', () {
    testWidgets('PaymentStatusScreen shows Lottie ONLY on confirmed PaymentVerificationState.successful',
        (WidgetTester tester) async {
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
      await tester.pump(const Duration(milliseconds: 300));

      // Pending verification: NO success Lottie
      expect(find.text('Payment Pending Verification'), findsOneWidget);
      expect(find.byType(Lottie), findsNothing);

      // Failed state: NO success Lottie
      await tester.ensureVisible(find.text('Simulate Failed'));
      await tester.tap(find.text('Simulate Failed'));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(find.text('Payment Failed'), findsOneWidget);
      expect(find.byType(Lottie), findsNothing);

      // Reset to Pending and verify Cancelled state has NO success Lottie
      await tester.pumpWidget(
        const MaterialApp(
          key: ValueKey('fresh-status'),
          home: PaymentStatusScreen(
            paymentData: {
              'invoiceId': 'INV-2026-011',
              'amount': 8000,
              'paymentApp': 'Google Pay',
              'txnRef': 'UPI-20261029-654321',
              'autoPoll': false,
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Simulate Cancelled'));
      await tester.tap(find.text('Simulate Cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Cancelled'), findsOneWidget);
      expect(find.byType(Lottie), findsNothing);

      // Reset to Pending and confirm via Simulate Settlement -> Lottie appears and settles
      await tester.pumpWidget(
        const MaterialApp(
          key: ValueKey('settled-status'),
          home: PaymentStatusScreen(
            paymentData: {
              'invoiceId': 'INV-2026-012',
              'amount': 8000,
              'paymentApp': 'Google Pay',
              'txnRef': 'UPI-20261029-999000',
              'autoPoll': false,
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Simulate Settlement'));
      await tester.tap(find.text('Simulate Settlement'));
      await tester.pumpAndSettle();

      expect(find.text('Payment Successful!'), findsOneWidget);
      expect(find.byType(Lottie), findsOneWidget);
    });

    testWidgets('ReceiptScreen renders confirmed payment Lottie and settles cleanly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ReceiptScreen(
            receiptData: {
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
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('VERIFIED & PAID'), findsOneWidget);
      expect(find.byType(Lottie), findsOneWidget);
    });

    testWidgets('NoticesScreen integrates bounded Lottie ONLY in empty state and settles',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const NoticesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Lottie), findsNothing);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Nothing Here Yet'), findsOneWidget);
      expect(find.byType(Lottie), findsOneWidget);
    });
  });

  group('Animated screens & smooth GoRouter page transitions', () {
    testWidgets('RentPaymentScreen, RentDepositScreen, ComplaintsScreen, LoginScreen and appRouter settle without error',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      for (final screen in <Widget>[
        const RentPaymentScreen(invoiceData: {'invoice_number': 'INV-2026-010', 'amount': 8000}),
        const RentDepositScreen(),
        const ComplaintsScreen(),
        const LoginScreen(),
      ]) {
        await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
        await tester.pumpAndSettle();
      }

      appRouter.go('/login');
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: appRouter));
      await tester.pumpAndSettle();
      expect(find.text('PG Pilot'), findsOneWidget);

      appRouter.go('/register');
      await tester.pumpAndSettle();
      expect(find.text('Self-onboarding'), findsOneWidget);

      appRouter.go('/login');
      await tester.pumpAndSettle();
      expect(find.text('PG Pilot'), findsOneWidget);
    });
  });
}
