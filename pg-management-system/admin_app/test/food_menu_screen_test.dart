import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:admin_app/features/food_menu/food_menu_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Admin FoodMenuScreen renders 7 days and saves menu', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FoodMenuScreen())));
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Food Menu'), findsOneWidget);

    // Verify Save buttons
    expect(find.text('Save Menu'), findsOneWidget);
    expect(find.text('Save Weekly Menu'), findsOneWidget);

    // Verify Days
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);

    // Tap Save Menu button
    await tester.tap(find.text('Save Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify green snackbar shows
    expect(find.text('Food menu saved successfully!'), findsOneWidget);
  });
}
