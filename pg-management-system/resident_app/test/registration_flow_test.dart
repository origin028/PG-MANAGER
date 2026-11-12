import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/core/services/resident_auth_service.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/auth/login_screen.dart';
import 'package:resident_app/features/auth/register_screen.dart';

void main() {
  group('Resident App Registration and Auth Flow', () {
    testWidgets('Login screen displays New Registration button and opens registration form',
        (WidgetTester tester) async {
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

    testWidgets('RegisterScreen renders redesigned HTML onboarding sections without hardcoded 123456 demo OTP',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const RegisterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // App bar, banner, and section verifications
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Self-onboarding'), findsOneWidget);
      expect(find.text('Select PG property'), findsOneWidget);
      expect(find.text('1. Personal information'), findsOneWidget);
      expect(find.text('2. Contact information'), findsOneWidget);
      expect(find.text('3. Permanent address'), findsOneWidget);
      expect(find.text('4. Identity & verification (KYC)'), findsOneWidget);

      // Verify KYC segmented method options
      expect(find.text('Aadhaar'), findsOneWidget);
      expect(find.text('Passport'), findsOneWidget);
      expect(find.text('Aadhaar card (front)'), findsOneWidget);
      expect(find.text('Aadhaar card (back)'), findsOneWidget);
      expect(find.text('PAN card'), findsOneWidget);
      expect(find.text('Resident selfie'), findsOneWidget);

      // Sticky bottom submission area
      expect(find.text('Register & verify OTP'), findsOneWidget);
      expect(find.text('Go to login'), findsOneWidget);

      // Verify zero hardcoded demo OTP
      expect(find.text('123456'), findsNothing);
      expect(find.textContaining('Demo OTP: 123456'), findsNothing);
    });

    testWidgets('RegisterScreen validates required fields before requesting OTP',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const RegisterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final submitButton = find.text('Register & verify OTP');
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Verify field validation errors
      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Select DOB'), findsOneWidget);
      expect(find.text('Enter occupation'), findsOneWidget);
      expect(find.text('Enter permanent address'), findsOneWidget);
    });

    testWidgets('RegisterScreen demo button populates mock files, updates progress, and switches KYC method cleanly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const RegisterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Demo auto-fill
      final demoButton = find.text('Demo');
      expect(demoButton, findsOneWidget);
      await tester.tap(demoButton);
      await tester.pumpAndSettle();

      // Verify auto-filled resident information and uploaded state
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('9876500001'), findsOneWidget);
      expect(find.text('Change'), findsNWidgets(4));

      // Progress bar reaches 100% (widthFactor 1.0)
      final fullProgressBox = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(fullProgressBox.widthFactor, 1.0);

      // Switch to Passport
      final passportTab = find.text('Passport');
      await tester.ensureVisible(passportTab);
      await tester.tap(passportTab);
      await tester.pumpAndSettle();

      // Verify Passport upload box appears alongside Resident selfie
      expect(find.text('Passport document'), findsOneWidget);
      expect(find.text('Resident selfie'), findsOneWidget);
    });

    testWidgets('RegisterScreen renders Light & Dark themes cleanly across viewports 320-412 without overflow',
        (WidgetTester tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());

      for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        // Light mode check
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const RegisterScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(lightScaffold.backgroundColor, const Color(0xFFF2F5F4));
        expect(find.text('Create account'), findsOneWidget);
        expect(find.text('Register & verify OTP'), findsOneWidget);

        // Dark mode check
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: const RegisterScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(darkScaffold.backgroundColor, const Color(0xFF0B1417));
        expect(find.text('Create account'), findsOneWidget);
        expect(find.text('Register & verify OTP'), findsOneWidget);
      }
    });

    testWidgets('RegisterScreen preserves Back & Go to login callbacks and reduced motion mode',
        (WidgetTester tester) async {
      var switchedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: RegisterScreen(
              onSwitchToLogin: () => switchedCount++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(switchedCount, 1);

      await tester.tap(find.text('Go to login'));
      await tester.pump();
      expect(switchedCount, 2);
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
