import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/complaints/complaints_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ComplaintsScreen renders Light & Dark themes across mobile viewports without overflow',
    (WidgetTester tester) async {
      const viewports = [
        Size(320, 640),
        Size(360, 740),
        Size(390, 844),
        Size(412, 915),
      ];

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        // Light Theme
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ComplaintsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Complaints & Services'), findsOneWidget);
        expect(find.text('Total'), findsOneWidget);
        expect(find.text('In Progress'), findsWidgets);
        expect(find.text('Resolved'), findsWidgets);
        expect(find.text('Raise Request'), findsOneWidget);
        expect(find.text('Call Desk'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Dark Theme
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const ComplaintsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Complaints & Services'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      tester.view.resetPhysicalSize();
    },
  );

  testWidgets(
    'ComplaintsScreen category filter chips and Raise Request bottom sheet interaction',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const ComplaintsScreen()),
      );
      await tester.pumpAndSettle();

      // Verify filter chips exist
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Plumbing'), findsWidgets);
      expect(find.text('Electrical'), findsWidgets);
      expect(find.text('Wi-Fi'), findsWidgets);

      // Tap Plumbing filter chip
      await tester.tap(find.text('Plumbing').first);
      await tester.pumpAndSettle();

      // Open Raise Request modal
      await tester.tap(find.text('Raise Request'));
      await tester.pumpAndSettle();

      expect(find.text('Raise Service Request'), findsOneWidget);
      expect(find.text('Submit Request'), findsOneWidget);

      // Enter title & description
      await tester.enterText(
        find.byType(TextField).first,
        'Water leakage in bathroom',
      );
      await tester.pump();

      // Submit Request
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      // Modal closed and snackbar or new ticket visible
      expect(find.text('Raise Service Request'), findsNothing);
      expect(find.text('Water leakage in bathroom'), findsOneWidget);
    },
  );
}
