import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/profile/call_management_screen.dart';

void main() {
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, null);
  });

  testWidgets(
      'CallManagementScreen renders Light & Dark themes across narrow and mobile viewports without overflow',
      (WidgetTester tester) async {
    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('call_light_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const CallManagementScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('Call Management'), findsOneWidget);
      expect(find.text('Direct property support'), findsOneWidget);
      expect(find.text('Property Owner'), findsOneWidget);
      expect(find.text('RK'), findsOneWidget);
      expect(find.text('Rajesh Kumar'), findsOneWidget);
      expect(find.text('PG Owner • Available 8 AM - 10 PM'), findsOneWidget);
      expect(find.text('Manager phone · tap to call'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsNWidgets(2));
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('WhatsApp desk · tap to chat'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Night Caretaker & Security'), findsOneWidget);
      expect(find.text('Gate Security & Caretaker'), findsOneWidget);
      expect(find.text('+91 9876543211 · 24/7 Desk'), findsOneWidget);
      expect(find.byTooltip('Call Caretaker'), findsOneWidget);

      // Dark theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('call_dark_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const CallManagementScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Call Management'), findsOneWidget);
      expect(find.text('Property Owner'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
  });

  testWidgets(
      'CallManagementScreen invokes Call and WhatsApp actions with fallback snackbars when dialer unavailable',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
      if (call.method == 'canLaunch') {
        return false;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CallManagementScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Tapping Call triggers _makePhoneCall for manager phone
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(find.text('Could not launch dialer for 9876543210'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(CallManagementScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    // Tapping Chat triggers _openWhatsApp for manager WhatsApp
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open WhatsApp for 919876543210'),
      findsOneWidget,
    );

    ScaffoldMessenger.of(
      tester.element(find.byType(CallManagementScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    // Tapping Caretaker button triggers _makePhoneCall for caretaker phone
    await tester.tap(find.byTooltip('Call Caretaker'));
    await tester.pumpAndSettle();
    expect(find.text('Could not launch dialer for 9876543211'), findsOneWidget);
  });

  testWidgets(
      'CallManagementScreen honors reduced motion, Refresh action, and GoRouter back navigation',
      (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/menu',
      routes: [
        GoRoute(
          path: '/menu',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/call-management'),
                child: const Text('Go Call'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/call-management',
          builder: (context, state) => const CallManagementScreen(),
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

    await tester.tap(find.text('Go Call'));
    await tester.pumpAndSettle();
    expect(find.text('Call Management'), findsOneWidget);

    // Refresh works cleanly
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Rajesh Kumar'), findsOneWidget);

    // Back pops cleanly back to /menu
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Go Call'), findsOneWidget);
  });
}

