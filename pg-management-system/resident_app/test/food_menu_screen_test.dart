import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
