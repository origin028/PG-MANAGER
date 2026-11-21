import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_app/features/payments/payments_screen.dart';

void main() {
  testWidgets('Admin PaymentsScreen renders Invoices and UPI Reconciliation Queue switcher cleanly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaymentsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Rent & Payments'), findsOneWidget);
    expect(find.text('Rent Invoices'), findsOneWidget);
    // UPI Reconciliation renamed to Verification Queue
    expect(find.textContaining('Verification Queue'), findsOneWidget);
    expect(find.textContaining('UPI Reconciliation'), findsNothing);

    // Switch to Verification Queue tab
    await tester.tap(find.textContaining('Verification Queue'));
    await tester.pump();

    expect(find.text('All Transactions'), findsOneWidget);
    expect(find.text('Pending Verification'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Failed / Cancelled'), findsOneWidget);
  });
}

