import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_app/core/widgets/app_dropdown.dart';

void main() {
  testWidgets('AppDropdown renders and selects item', (WidgetTester tester) async {
    String selected = 'All KYC Statuses';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return AppDropdown.simple(
                    value: selected,
                    items: const ['All KYC Statuses', 'Verified', 'Pending', 'Rejected'],
                    onChanged: (v) {
                      setState(() => selected = v);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Initial value is shown
    expect(find.text('All KYC Statuses'), findsOneWidget);

    // Tap dropdown
    await tester.tap(find.text('All KYC Statuses'));
    await tester.pumpAndSettle();

    // Menu options are shown
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);

    // Select 'Verified'
    await tester.tap(find.text('Verified'));
    await tester.pumpAndSettle();

    // Now selected is 'Verified'
    expect(selected, 'Verified');
  });
}
