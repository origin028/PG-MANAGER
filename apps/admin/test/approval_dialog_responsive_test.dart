import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:admin_app/core/theme/app_theme.dart';
import 'package:admin_app/core/data/app_data.dart';
import 'package:admin_app/features/dashboard/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppData.pendingResidents = [
      {
        'id': 'res-uuid-101',
        'name': 'Aarav Sharma',
        'phone': '9876543210',
        'email': 'aarav.sharma@example.com',
        'status': 'Pending Approval',
        'property_name': 'BNR Luxury PG',
        'raw': {
          'id': 'res-uuid-101',
          'full_name': 'Aarav Sharma',
          'phone': '9876543210',
          'email': 'aarav.sharma@example.com',
          'property_name': 'BNR Luxury PG',
          'date_of_birth': '1998-07-15',
          'gender': 'Male',
          'occupation': 'Software Engineer',
          'emergency_contact': '9876500001',
          'city': 'Bengaluru',
          'state': 'Karnataka',
          'pincode': '560100',
          'aadhaar_front_path': 'uploads/kyc/aadhaar_front.jpg',
          'aadhaar_back_path': 'uploads/kyc/aadhaar_back.jpg',
          'pan_card_path': 'uploads/kyc/pan.jpg',
          'resident_selfie_path': 'uploads/kyc/selfie.jpg',
        },
      },
    ];
  });

  const testViewports = <String, Size>{
    '1. Desktop FHD (1920x1080)': Size(1920, 1080),
    '2. Standard Laptop (1366x768)': Size(1366, 768),
    '3. 720p Laptop (1280x720)': Size(1280, 720),
    '4. Small Desktop / Tablet Landscape (1024x768)': Size(1024, 768),
    '5. Tablet Portrait (768x1024)': Size(768, 1024),
    '6. Mobile Viewport (390x844)': Size(390, 844),
  };

  for (final entry in testViewports.entries) {
    testWidgets('Assign Room & Rent dialog at viewport ${entry.key} renders cleanly with zero overflow', (WidgetTester tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify PendingApprovalsCard is displayed
      expect(find.byType(PendingApprovalsCard), findsOneWidget);
      expect(find.text('Review & Assign'), findsOneWidget);

      // Open the Approval Dialog
      await tester.tap(find.text('Review & Assign'));
      await tester.pumpAndSettle();

      // Verify Dialog Header
      expect(find.text('Assign Room & Rent'), findsOneWidget);

      // Verify Resident Information section
      expect(find.text('Aarav Sharma'), findsWidgets);
      expect(find.text('+91 9876543210'), findsWidgets);
      expect(find.text('aarav.sharma@example.com'), findsOneWidget);
      expect(find.text('Property: BNR Luxury PG'), findsOneWidget);

      // Verify KYC Documents section
      expect(find.text('KYC Documents Verification'), findsOneWidget);
      expect(find.text('Aadhaar Front'), findsOneWidget);
      expect(find.text('Aadhaar Back'), findsOneWidget);
      expect(find.text('PAN Card'), findsOneWidget);
      expect(find.text('Selfie Photo'), findsOneWidget);

      // Verify Room & Bed Allocation controls
      expect(find.text('Room & Bed Allocation'), findsOneWidget);
      expect(find.text('Room Number *'), findsOneWidget);
      expect(find.text('Available Bed *'), findsOneWidget);
      expect(find.text('Monthly Rent (₹) *'), findsOneWidget);
      expect(find.text('Payment Due Date *'), findsOneWidget);

      // Verify Sticky Action Buttons are present and accessible
      expect(find.text('Reject Application'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm & Assign'), findsOneWidget);

      // Close dialog via Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.text('Assign Room & Rent'), findsNothing);
    });
  }

  testWidgets('Assign Room & Rent dialog allows full approval workflow without errors', (WidgetTester tester) async {
    AppData.pendingResidents = [
      {'name': 'Aarav Sharma', 'phone': '9876543210', 'status': 'Pending Approval'},
    ];
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review & Assign'));
    await tester.pumpAndSettle();

    // Tap Confirm & Assign
    await tester.tap(find.text('Confirm & Assign'));
    await tester.pumpAndSettle();

    // Dialog closed, resident removed from pending
    expect(find.text('Assign Room & Rent'), findsNothing);
    expect(AppData.pendingResidents.isEmpty, isTrue);
  });
}
