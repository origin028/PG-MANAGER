import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/features/auth/login_screen.dart';
import 'package:resident_app/features/auth/register_screen.dart';
import 'package:resident_app/core/services/resident_auth_service.dart';

void main() {
  group('Resident App Registration and Auth Flow', () {
    testWidgets('Login screen displays New Registration button and opens registration form', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final newRegButton = find.text('New Registration');
      expect(newRegButton, findsOneWidget);

      await tester.tap(newRegButton);
      await tester.pumpAndSettle();

      expect(find.text('New Resident Registration'), findsOneWidget);
      expect(find.text('Full Name *'), findsOneWidget);
      expect(find.text('Phone Number *'), findsOneWidget);
      expect(find.text('Submit Registration'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), 'Rohan Mehta');
      await tester.enterText(find.byType(TextField).at(2), '9876543290');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Registration'));
      await tester.pumpAndSettle();

      expect(find.text('New Resident Registration'), findsNothing);
      expect(find.text('Registration request sent to Admin. Please wait for approval.'), findsOneWidget);
    });

    testWidgets('RegisterScreen renders full onboarding form without hardcoded 123456 demo OTP', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RegisterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Form header and section verifications
      expect(find.text('Self-Onboarding Portal'), findsOneWidget);
      expect(find.text('Select PG Property'), findsOneWidget);
      expect(find.text('1. Personal Information'), findsOneWidget);
      expect(find.text('2. Contact Information'), findsOneWidget);
      expect(find.text('3. Permanent Address'), findsOneWidget);
      expect(find.text('4. Identity & Verification (KYC)'), findsOneWidget);

      // Verify KYC document selection options
      expect(find.text('Aadhaar + PAN'), findsOneWidget);
      expect(find.text('Passport Only'), findsOneWidget);

      // Verify submit button
      expect(find.text('Register & Verify OTP'), findsOneWidget);

      // VERIFY ABSOLUTELY NO HARDCODED DEMO OTP ANYWHERE
      expect(find.text('123456'), findsNothing);
      expect(find.textContaining('Demo OTP: 123456'), findsNothing);
    });

    testWidgets('RegisterScreen validates required fields before requesting OTP', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RegisterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to submit button and tap
      final submitButton = find.text('Register & Verify OTP');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Should show field validation errors
      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Select DOB'), findsOneWidget);
      expect(find.text('Enter occupation'), findsOneWidget);
      expect(find.text('Enter permanent address'), findsOneWidget);
    });

    testWidgets('RegisterScreen demo button populates mock files and clears on document switch', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RegisterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Demo auto-fill
      final demoButton = find.text('Demo');
      expect(demoButton, findsOneWidget);
      await tester.tap(demoButton);
      await tester.pumpAndSettle();

      // Verify auto-filled resident information
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('9876500001'), findsOneWidget);

      // Switch to Passport Only
      final passportTab = find.text('Passport Only');
      await tester.ensureVisible(passportTab);
      await tester.tap(passportTab);
      await tester.pumpAndSettle();

      // Verify Passport upload box appears
      expect(find.text('Upload Passport Document *'), findsOneWidget);
    });

    test('ResidentAuthService getAvailableProperties returns active properties list', () async {
      final properties = await ResidentAuthService.getAvailableProperties();
      expect(properties, isNotEmpty);
      expect(properties.first.containsKey('id'), isTrue);
      expect(properties.first.containsKey('name'), isTrue);
      expect(properties.any((p) => p['name'].toString().contains('Origin Grand PG')), isTrue);
    });
  });
}
