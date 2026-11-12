import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/profile/profile_screen.dart';

void main() {
  late Map<String, dynamic> originalResident;

  setUp(() {
    originalResident = Map<String, dynamic>.from(AppData.currentResident);
  });

  tearDown(() {
    AppData.currentResident = originalResident;
  });

  testWidgets(
      'ProfileScreen renders Light & Dark themes cleanly across viewports without overflow',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1], // Priya Sharma, Room 101, Bed B, KYC Verified
      'living_since': '2026-10-01',
    };

    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('profile_light_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('PS'), findsOneWidget);
      expect(find.text('Priya Sharma'), findsNWidgets(2));
      expect(find.text('BNR Luxury PG · Room 101 · Bed B'), findsOneWidget);
      expect(find.text('KYC Verified'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);

      // Tri-metric strip
      expect(find.text('Room'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
      expect(find.text('Bed'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('Since'), findsOneWidget);
      expect(find.text('Oct 2026'), findsOneWidget);

      // Detail sections
      expect(find.text('Personal & Contact Details'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('priya.sharma@example.com'), findsOneWidget);
      expect(find.text('BNR Luxury PG, Koramangala'), findsOneWidget);
      expect(find.text('KYC & Identity Verification'), findsOneWidget);
      expect(find.text('Aadhaar card'), findsOneWidget);
      expect(find.text('PAN card'), findsOneWidget);
      expect(find.text('Uploaded'), findsNWidgets(2));

      // Dark theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('profile_dark_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
  });

  testWidgets(
      'ProfileScreen supports nested stay_details, pending KYC, Upload CTA & masked ID',
      (WidgetTester tester) async {
    AppData.currentResident = {
      'name': 'Rohan Mehta',
      'phone': '+919876543290',
      'email': 'rohan.mehta@example.com',
      'kyc': 'Pending',
      'stay_details': {
        'property_name': 'GreenView Residency',
        'property_address': 'Indiranagar 100ft Rd, Bengaluru',
        'room_number': '204',
        'bed_number': 'Bed C',
        'living_since': '2025-03-14',
      },
      'kyc_details': {
        'kyc_status': 'Pending',
        'id_proof_type': 'Aadhaar',
        'id_proof_number_masked': 'XXXX-XXXX-4321',
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RM'), findsOneWidget);
    expect(find.text('Rohan Mehta'), findsNWidgets(2));
    expect(find.text('GreenView Residency · Room 204 · Bed C'), findsOneWidget);
    expect(find.text('KYC Pending Verification'), findsOneWidget);
    expect(find.text('204'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('Mar 2025'), findsOneWidget);
    expect(find.text('+919876543290'), findsOneWidget);
    expect(find.text('Indiranagar 100ft Rd, Bengaluru'), findsOneWidget);
    expect(find.text('Not Uploaded Yet'), findsNWidgets(2));
    expect(find.text('Upload'), findsNWidgets(2));
  });

  testWidgets(
      'Edit Profile modal keeps Email read-only, validates input, and updates resident profile',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Edit Profile modal
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Update your personal information below.'), findsOneWidget);
    expect(find.text('(Read-only)'), findsOneWidget);

    // Email field must be strictly disabled/read-only
    final formFields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(formFields.length, 3);
    expect(formFields[2].enabled, isFalse);

    // Trigger validation failure with invalid phone
    await tester.enterText(find.byType(TextFormField).at(0), '');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Please enter a valid 10-digit mobile number'), findsOneWidget);

    // Enter valid name & phone and save
    await tester.enterText(find.byType(TextFormField).at(0), 'Ananya Verma');
    await tester.enterText(find.byType(TextFormField).at(1), '9123456789');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(AppData.currentResident['name'], 'Ananya Verma');
    expect(AppData.currentResident['phone'], '9123456789');
    expect(find.text('AV'), findsOneWidget);
    expect(find.text('Ananya Verma'), findsNWidgets(2));
    expect(find.text('+91 9123456789'), findsOneWidget);
    expect(find.text('Profile updated successfully!'), findsOneWidget);
  });

  testWidgets(
      'Camera badge updates selfie photo feedback, honors reduced motion, and GoRouter back pops cleanly',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
    };

    final router = GoRouter(
      initialLocation: '/menu',
      routes: [
        GoRoute(
          path: '/menu',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/profile'),
                child: const Text('Go Profile'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go Profile'));
    await tester.pumpAndSettle();
    expect(find.text('My Profile'), findsOneWidget);

    // Tapping camera icon triggers FilePicker fallback simulation in tests
    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Profile photo updated successfully!'), findsOneWidget);

    // Tapping back pops to /menu
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Go Profile'), findsOneWidget);
  });
}

