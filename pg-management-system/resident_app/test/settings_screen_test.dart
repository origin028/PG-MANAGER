import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/profile/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Map<String, dynamic> originalResident;
  late ThemeMode originalThemeMode;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalResident = Map<String, dynamic>.from(AppData.currentResident);
    originalThemeMode = AppTheme.themeModeNotifier.value;
    AppTheme.themeModeNotifier.value = ThemeMode.light;
  });

  tearDown(() {
    AppData.currentResident = originalResident;
    AppTheme.themeModeNotifier.value = originalThemeMode;
  });

  testWidgets(
      'SettingsScreen renders Light & Dark themes across narrow and mobile viewports without overflow',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1], // Priya Sharma, Room 101
    };

    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('settings_light_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('PS'), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('BNR Luxury PG · Room 101'), findsOneWidget);
      expect(find.text('KYC'), findsOneWidget);
      expect(find.text('App Preferences'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('App Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Rent Reminders'), findsOneWidget);
      expect(find.text('Maintenance Alerts'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
      expect(find.text('Account Details'), findsNothing);
      expect(
        find.text('PG Pilot Resident App • Version 1.0.0 (Build 2026)'),
        findsNothing,
      );

      // Dark theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('settings_dark_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
  });

  testWidgets(
      'SettingsScreen updates theme switch, language dropdown, and notification toggles',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
    };

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: AppTheme.themeModeNotifier,
        builder: (context, mode, child) {
          return MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: const SettingsScreen(),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Toggle Dark Mode switch (Switch #0)
    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    expect(AppTheme.themeModeNotifier.value, ThemeMode.dark);
    expect(find.text('Dark mode enabled'), findsOneWidget);

    // Change Language dropdown
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hindi').last);
    await tester.pumpAndSettle();
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('Language changed to Hindi'), findsOneWidget);

    // Toggle Rent Reminders & Maintenance Alerts switches
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);

    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, isTrue);
    await tester.tap(find.byType(Switch).at(2));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, isFalse);
  });

  testWidgets(
      'SettingsScreen Logout dialog confirms & navigates to /login, POC links & Back work cleanly',
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
                onPressed: () => context.push('/settings'),
                child: const Text('Go Settings'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/poc-upi-india',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('POC India Page'))),
        ),
        GoRoute(
          path: '/poc-upi-pay',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('POC Pay Page'))),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Login Page'))),
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

    await tester.tap(find.text('Go Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    // Back pops cleanly
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Go Settings'), findsOneWidget);

    // Re-enter Settings & test POC navigation
    await tester.tap(find.text('Go Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('UPI Package POC (flutter_upi_india)'),
    );
    await tester.tap(find.text('UPI Package POC (flutter_upi_india)'));
    await tester.pumpAndSettle();
    expect(find.text('POC India Page'), findsOneWidget);

    // Pop back to Settings, open Logout dialog -> Cancel -> Logout
    router.pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Logout'), findsOneWidget);

    // Cancel keeps user in Settings
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Logout'), findsNothing);

    // Confirm Logout navigates to /login
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log Out'));
    await tester.pumpAndSettle();
    expect(find.text('Login Page'), findsOneWidget);
  });
}

