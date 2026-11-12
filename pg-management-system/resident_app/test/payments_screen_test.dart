import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/core/widgets/main_layout.dart';
import 'package:resident_app/features/payments/payments_screen.dart';

void main() {
  testWidgets(
      'PaymentsScreen renders Current Cycle card, invoices, Light & Dark themes cleanly across widths 360-412',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1], // Priya Sharma, room 101, rent 8000
      'property': 'BNR Luxury PG',
      'rent_status': 'Pending',
    };

    for (final width in [360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light Theme verification
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const MainLayout(child: PaymentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(PaymentsScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('BNR Luxury PG · Room 101'), findsOneWidget);
      expect(find.text('Rent & Payments'), findsOneWidget);
      expect(find.text('CURRENT CYCLE'), findsOneWidget);
      expect(find.text('8,000'), findsOneWidget);
      expect(find.text('Pay rent now'), findsOneWidget);
      expect(find.text('Payment history & invoices'), findsOneWidget);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Pay now'), findsOneWidget);
      expect(find.text('Paid'), findsNWidgets(2));
      expect(find.text('Receipt'), findsNWidgets(2));
      expect(find.text('₹8,000'), findsNWidgets(3));

      // Dark Theme verification
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const MainLayout(child: PaymentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(PaymentsScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Rent & Payments'), findsOneWidget);
      expect(find.text('Pay rent now'), findsOneWidget);
      expect(find.text('Pay now'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
  });

  testWidgets('PaymentsScreen renders settled Paid state and View latest receipt',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
      'rent_status': 'Paid',
      'stay_details': {
        'property_name': 'Sunrise Residency',
        'room_number': '204',
        'monthly_rent': 9500,
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const PaymentsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Residency · Room 204'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('All dues cleared for this month'), findsOneWidget);
    expect(find.text('View latest receipt'), findsOneWidget);
    expect(find.text('Pay rent now'), findsNothing);
    expect(find.text('Pay now'), findsNothing);
    expect(find.text('Receipt'), findsNWidgets(3));
    expect(find.text('₹9,500'), findsNWidgets(3));
  });

  testWidgets(
      'PaymentsScreen preserves existing navigation to /rent-payment and /receipt',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
      'rent': 8000,
      'rent_status': 'Pending',
    };

    String? pushedRoute;
    Map<String, dynamic>? pushedExtra;

    final router = GoRouter(
      initialLocation: '/payments',
      routes: [
        GoRoute(
          path: '/payments',
          builder: (context, state) => const PaymentsScreen(),
        ),
        GoRoute(
          path: '/rent-payment',
          builder: (context, state) {
            pushedRoute = '/rent-payment';
            pushedExtra = state.extra as Map<String, dynamic>?;
            return Scaffold(
              body: Text('RentPayment:${pushedExtra?['id']}:${pushedExtra?['autoOpen']}'),
            );
          },
        ),
        GoRoute(
          path: '/receipt',
          builder: (context, state) {
            pushedRoute = '/receipt';
            pushedExtra = state.extra as Map<String, dynamic>?;
            return Scaffold(
              body: Text('Receipt:${pushedExtra?['invoiceId']}:${pushedExtra?['amount']}'),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    // Test Hero Pay rent now navigation
    await tester.tap(find.text('Pay rent now'));
    await tester.pumpAndSettle();
    expect(pushedRoute, '/rent-payment');
    expect(pushedExtra?['id'], 'INV-2026-010');
    expect(pushedExtra?['autoOpen'], true);

    // Pop back to /payments
    router.pop();
    await tester.pumpAndSettle();

    // Test Card Pay now navigation
    await tester.tap(find.text('Pay now'));
    await tester.pumpAndSettle();
    expect(pushedRoute, '/rent-payment');
    expect(pushedExtra?['id'], 'INV-2026-010');

    // Pop back to /payments
    router.pop();
    await tester.pumpAndSettle();

    // Test Receipt navigation (scroll down slightly if needed)
    await tester.ensureVisible(find.text('Receipt').first);
    await tester.tap(find.text('Receipt').first);
    await tester.pumpAndSettle();
    expect(pushedRoute, '/receipt');
    expect(pushedExtra?['invoiceId'], 'INV-2026-009');
    expect(pushedExtra?['amount'], 8000.0);
    expect(pushedExtra?['month'], 'October 2026');
  });

  testWidgets('PaymentsScreen honors reduced motion MediaQuery without errors',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
      'rent_status': 'Pending',
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: PaymentsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Rent & Payments'), findsOneWidget);
    expect(find.text('Pay rent now'), findsOneWidget);
  });
}

