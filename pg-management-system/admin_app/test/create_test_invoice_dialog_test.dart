import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:admin_app/core/network/token_storage.dart';
import 'package:admin_app/features/payments/create_test_invoice_dialog.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TokenStorage.init();
    await TokenStorage.saveTokens(
      accessToken: 'dummy_access',
      refreshToken: 'dummy_refresh',
      user: {'role': 'SUPER_ADMIN'},
    );
  });

  testWidgets('TokenStorage user role checks work as expected', (tester) async {
    await TokenStorage.saveTokens(
      accessToken: 'dummy_access',
      refreshToken: 'dummy_refresh',
      user: {'role': 'SUPER_ADMIN'},
    );
    expect(TokenStorage.userRole, 'SUPER_ADMIN');
    expect(TokenStorage.canManageInvoices, isTrue);

    await TokenStorage.saveTokens(
      accessToken: 'dummy_access',
      refreshToken: 'dummy_refresh',
      user: {'role': 'PROPERTY_MANAGER'},
    );
    expect(TokenStorage.canManageInvoices, isTrue);

    await TokenStorage.saveTokens(
      accessToken: 'dummy_access',
      refreshToken: 'dummy_refresh',
      user: {'role': 'RESIDENT'},
    );
    expect(TokenStorage.canManageInvoices, isFalse);
  });

  testWidgets('CreateTestInvoiceDialog renders with fixed ₹1.00 test amount', (tester) async {
    await TokenStorage.saveTokens(
      accessToken: 'dummy_access',
      refreshToken: 'dummy_refresh',
      user: {'role': 'SUPER_ADMIN'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => CreateTestInvoiceDialog.show(context, onInvoiceCreated: () {}),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify dialog title, button and header
    expect(find.text('Create Test Invoice'), findsNWidgets(2)); // Title and submit button
    expect(find.text('Safe ₹1.00 UPI verification invoice'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('₹ 1.00'), findsOneWidget);
    expect(find.text('(Fixed)'), findsOneWidget);
    expect(find.text('Invoice Type'), findsOneWidget);
    expect(find.text('TEST'), findsOneWidget);
    expect(find.text('₹1 UPI Integration Test Invoice'), findsOneWidget);
  });
}
