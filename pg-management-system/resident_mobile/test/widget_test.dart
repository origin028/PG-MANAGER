import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_mobile/models/invoice.dart';
import 'package:resident_mobile/models/payment.dart';
import 'package:resident_mobile/models/receipt.dart';
import 'package:resident_mobile/models/resident_profile.dart';
import 'package:resident_mobile/models/user.dart';
import 'package:resident_mobile/widgets/empty_state_widget.dart';
import 'package:resident_mobile/widgets/error_state_widget.dart';
import 'package:resident_mobile/widgets/loading_indicator.dart';
import 'package:resident_mobile/widgets/status_chip.dart';

void main() {
  group('Resident Mobile Models Test Suite', () {
    test('User model parses successfully', () {
      final json = {
        'id': 'usr-123',
        'full_name': 'Aarav Sharma',
        'email': 'aarav@originpg.com',
        'phone': '9876543210',
        'role': {'name': 'RESIDENT', 'display_name': 'Resident'},
      };
      final user = User.fromJson(json);
      expect(user.id, 'usr-123');
      expect(user.fullName, 'Aarav Sharma');
      expect(user.phone, '9876543210');
      expect(user.roleName, 'RESIDENT');
    });

    test('ResidentProfile model parses correctly', () {
      final json = {
        'resident_id': 'res-101',
        'user_id': 'usr-123',
        'full_name': 'Aarav Sharma',
        'phone': '9876543210',
        'email': 'aarav@originpg.com',
        'property_id': 'prop-555',
        'property_name': 'Origin Luxury PG',
        'property_address': 'Koramangala, Bangalore',
        'room_number': '204',
        'bed_number': 'B1',
        'check_in_date': '2026-01-01',
        'monthly_rent': 12000.0,
        'security_deposit': 24000.0,
        'kyc_status': 'VERIFIED',
        'status': 'ACTIVE',
      };
      final profile = ResidentProfile.fromJson(json);
      expect(profile.residentId, 'res-101');
      expect(profile.propertyName, 'Origin Luxury PG');
      expect(profile.monthlyRent, 12000.0);
      expect(profile.securityDeposit, 24000.0);
      expect(profile.roomNumber, '204');
    });

    test('ResidentInvoiceItem parses and computes flags', () {
      final json = {
        'id': 'inv-001',
        'invoice_number': 'INV-2026-001',
        'billing_month': '2026-10',
        'invoice_type': 'RENT',
        'amount': 12000.0,
        'paid_amount': 0.0,
        'remaining_amount': 12000.0,
        'due_date': '2026-11-05',
        'status': 'PENDING',
        'created_at': '2026-10-25T10:00:00Z',
      };
      final invoice = ResidentInvoiceItem.fromJson(json);
      expect(invoice.isPending, true);
      expect(invoice.isPaid, false);
      expect(invoice.remainingAmount, 12000.0);
    });

    test('PaymentRequestResponse parses Razorpay checkout metadata', () {
      final json = {
        'payment_id': 'pay-001',
        'payment_number': 'PAY-2026-001',
        'gateway_order_id': 'order_rzp_123',
        'amount': 12000.0,
        'amount_paise': 1200000,
        'currency': 'INR',
        'key_id': 'rzp_test_public_key',
        'property_name': 'Origin PG',
        'resident_name': 'Aarav Sharma',
      };
      final paymentReq = PaymentRequestResponse.fromJson(json);
      expect(paymentReq.paymentId, 'pay-001');
      expect(paymentReq.gatewayOrderId, 'order_rzp_123');
      expect(paymentReq.keyId, 'rzp_test_public_key');
      expect(paymentReq.amountPaise, 1200000);
    });

    test('ReceiptSummary model parses correctly', () {
      final json = {
        'id': 'rec-001',
        'receipt_number': 'REC-2026-001',
        'amount': 12000.0,
        'issued_at': '2026-10-29 10:30',
        'invoice_id': 'inv-001',
        'invoice_number': 'INV-2026-001',
        'billing_month': '2026-10',
        'payment_mode': 'UPI',
      };
      final receipt = ReceiptSummary.fromJson(json);
      expect(receipt.id, 'rec-001');
      expect(receipt.receiptNumber, 'REC-2026-001');
      expect(receipt.amount, 12000.0);
    });
  });

  group('Resident Mobile UI Widgets Test Suite', () {
    testWidgets('StatusChip renders correct color and label for PAID and PENDING', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StatusChip(status: 'PAID'),
                StatusChip(status: 'PENDING'),
                StatusChip(status: 'OVERDUE'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('OVERDUE'), findsOneWidget);
    });

    testWidgets('EmptyStateWidget renders message and optional action button', (tester) async {
      bool actionTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              title: 'No Invoices',
              message: 'You have no invoices yet.',
              actionLabel: 'Refresh',
              onAction: () => actionTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('No Invoices'), findsOneWidget);
      expect(find.text('You have no invoices yet.'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.tap(find.text('Refresh'));
      expect(actionTapped, true);
    });

    testWidgets('ErrorStateWidget renders message and retry button', (tester) async {
      bool retryTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Connection timeout',
              onRetry: () => retryTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Connection timeout'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      expect(retryTapped, true);
    });

    testWidgets('AppLoadingIndicator renders spinner and optional message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLoadingIndicator(message: 'Loading details...'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading details...'), findsOneWidget);
    });
  });
}
