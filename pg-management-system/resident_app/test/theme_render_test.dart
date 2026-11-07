import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/core/widgets/main_layout.dart';
import 'package:resident_app/features/home/home_screen.dart';
import 'package:resident_app/features/food_menu/food_menu_screen.dart';
import 'package:resident_app/features/payments/payments_screen.dart';
import 'package:resident_app/features/profile/property_details_screen.dart';
import 'package:resident_app/features/profile/call_management_screen.dart';
import 'package:resident_app/features/profile/settings_screen.dart';
import 'package:resident_app/features/complaints/raise_complaint_screen.dart';

void main() {
  testWidgets('HomeScreen in MainLayout with AppTheme renders and hit tests across wide web screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const MainLayout(child: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    // Verify key widgets
    expect(find.text('YOUR STAY'), findsOneWidget);
    expect(find.text('Notices'), findsWidgets);
    expect(find.text('Recent Payments'), findsNothing);

    // Simulate mouse movements across the screen to test MouseTracker hit tests
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    for (double x = 0; x < 1200; x += 100) {
      for (double y = 0; y < 800; y += 100) {
        await gesture.moveTo(Offset(x, y));
        await tester.pump();
      }
    }
  });

  testWidgets('HomeScreen on mobile viewport with mouse hover in Dark Theme', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const MainLayout(child: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('YOUR STAY'), findsOneWidget);
    expect(find.text('Notices'), findsWidgets);
  });

  testWidgets('FoodMenuScreen renders in Dark Theme and narrow viewport (320px) without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const FoodMenuScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Weekly Food Menu'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
  });

  testWidgets('PaymentsScreen renders in Dark Theme and narrow viewport (320px) without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const PaymentsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rent & Payments'), findsOneWidget);
    expect(find.text('MONTHLY RENT'), findsOneWidget);
  });

  testWidgets('PropertyDetailsScreen renders in Dark Theme and narrow viewport (320px) without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const PropertyDetailsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Property Details'), findsOneWidget);
    expect(find.text('Room Number'), findsOneWidget);
    expect(find.text('Floor'), findsOneWidget);
  });

  testWidgets('CallManagementScreen renders in Dark Theme and narrow viewport (320px) without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const CallManagementScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Call Management'), findsOneWidget);
    expect(find.text('Property Owner'), findsOneWidget);
  });

  testWidgets('RaiseComplaintScreen renders in Dark Theme and narrow viewport (320px) without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const RaiseComplaintScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Raise Complaint'), findsOneWidget);
    expect(find.text('Complaint Category *'), findsOneWidget);
  });

  testWidgets('SettingsScreen toggles Dark Theme mode via ValueNotifier', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppTheme.themeModeNotifier.value = ThemeMode.light;

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

    expect(find.text('Dark Mode'), findsOneWidget);
    final switchFinder = find.byType(Switch).first;
    expect(switchFinder, findsOneWidget);

    // Tap dark mode toggle switch
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Verify themeModeNotifier switched to dark
    expect(AppTheme.themeModeNotifier.value, ThemeMode.dark);

    // Tap again to switch back
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(AppTheme.themeModeNotifier.value, ThemeMode.light);
  });
}
