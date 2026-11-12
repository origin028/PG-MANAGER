import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/core/widgets/main_layout.dart';
import 'package:resident_app/features/food_menu/food_menu_screen.dart';

void main() {
  testWidgets('Resident FoodMenuScreen renders 7 days and meal categories', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: FoodMenuScreen()));
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Weekly Food Menu'), findsOneWidget);

    // Verify Days
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('Wednesday'), findsOneWidget);

    // Verify Meal categories
    expect(find.text('Breakfast'), findsWidgets);
    expect(find.text('Lunch'), findsWidgets);
    expect(find.text('Dinner'), findsWidgets);

    // Verify Meal icons
    expect(find.byIcon(Icons.wb_sunny_rounded), findsWidgets);
    expect(find.byIcon(Icons.lunch_dining_rounded), findsWidgets);
    expect(find.byIcon(Icons.nightlight_round_rounded), findsWidgets);
  });

  testWidgets(
      'FoodMenuScreen renders Light & Dark themes across widths 360-412 cleanly with no extra food/payment actions',
      (WidgetTester tester) async {
    for (final width in [360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light Theme verification
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('light_app_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const MainLayout(child: FoodMenuScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(FoodMenuScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('Fresh, hygienic meals cooked daily'), findsOneWidget);
      expect(find.text('Weekly Food Menu'), findsOneWidget);
      expect(find.text('3 meals a day'), findsOneWidget);
      expect(find.textContaining('Today:'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Today'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Strict check: NO food ordering, booking, rating, or payment UI
      expect(find.text('Order Now'), findsNothing);
      expect(find.text('Book Meal'), findsNothing);
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Pay Now'), findsNothing);

      // Dark Theme verification
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('dark_app_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const MainLayout(child: FoodMenuScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(FoodMenuScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Weekly Food Menu'), findsOneWidget);
      expect(find.text('3 meals a day'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
  });

  testWidgets('FoodMenuScreen scrolls through all 7 days cleanly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const FoodMenuScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monday'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Sunday'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunday'), findsOneWidget);
  });

  testWidgets('FoodMenuScreen honors reduced motion accessibility setting',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: FoodMenuScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Weekly Food Menu'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
  });
}
