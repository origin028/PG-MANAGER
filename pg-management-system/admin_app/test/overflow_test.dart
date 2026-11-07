import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:admin_app/core/theme/app_theme.dart';
import 'package:admin_app/core/router/app_router.dart';
import 'package:admin_app/features/properties/properties_screen.dart';
import 'package:admin_app/features/properties/property_form_dialog.dart';
import 'package:admin_app/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Check for overflow on PropertiesScreen and Add Property Dialog on mobile (360x640)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: PropertiesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify PropertiesScreen renders header and summary cards without overflow
    expect(find.text('Manage Properties'), findsOneWidget);
    expect(find.text('Total Properties'), findsOneWidget);

    // Open Property Form Dialog
    showAddEditPropertyDialog(
      context: tester.element(find.byType(PropertiesScreen)),
    );
    await tester.pumpAndSettle();

    // Verify dialog opened without overflow
    expect(find.text('Add New Property'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Check for overflow on SettingsScreen and Logout Dialog on mobile (360x640)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to Log Out button and tap it
    final logoutBtn = find.text('Log Out of PG Owner');
    await tester.ensureVisible(logoutBtn);
    await tester.pumpAndSettle();
    await tester.tap(logoutBtn);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Logout'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Check for overflow on AdminLayout with Router on mobile (360x640)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    );
    await tester.pumpAndSettle();

    // Test all admin routes on mobile for zero pixel overflow
    final routes = [
      '/dashboard',
      '/properties',
      '/rooms',
      '/residents',
      '/payments',
      '/complaints',
      '/expenses',
      '/staff',
      '/leads',
      '/reports',
      '/food-menu',
      '/settings',
    ];

    for (final route in routes) {
      appRouter.go(route);
      await tester.pumpAndSettle();
    }

    // Navigate to /properties
    appRouter.go('/properties');
    await tester.pumpAndSettle();

    // Tap mobile Add Property in header
    final headerAddBtn = find.widgetWithText(ElevatedButton, 'Add Property');
    if (headerAddBtn.evaluate().isNotEmpty) {
      await tester.tap(headerAddBtn.first);
      await tester.pumpAndSettle();
      expect(find.text('Add New Property'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Check for overflow on AdminLayout at compact 320px width', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    );
    await tester.pumpAndSettle();

    appRouter.go('/dashboard');
    await tester.pumpAndSettle();

    // Verify Notification Bell icon is present in the top header
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

    // Tap Notification Bell to open modal
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    // Verify modal opened without overflow
    expect(find.text('Notifications'), findsOneWidget);

    // Close modal
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Test routes at 320px
    appRouter.go('/payments');
    await tester.pumpAndSettle();
    expect(find.text('Rent & Payments'), findsOneWidget);
  });

  testWidgets('Check for layout integrity on AdminLayout on Desktop (1280x800)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    );
    await tester.pumpAndSettle();

    appRouter.go('/dashboard');
    await tester.pumpAndSettle();

    expect(find.text('Good morning'), findsOneWidget);

    appRouter.go('/payments');
    await tester.pumpAndSettle();
    expect(find.text('Rent & Payments'), findsOneWidget);
    expect(find.text('Create Test Invoice'), findsOneWidget);
  });
}
