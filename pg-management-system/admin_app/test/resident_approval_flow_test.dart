import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_app/core/data/app_data.dart';
import 'package:admin_app/features/dashboard/dashboard_screen.dart';

void main() {
  setUp(() {
    // Reset test state
    AppData.pendingResidents = [
      {'name': 'Rohan Mehta', 'phone': '9876543290', 'status': 'Pending Approval'},
    ];
  });

  test('AppData pendingResidents has Rohan Mehta by default and assignResidentToRoom works', () {
    expect(AppData.pendingResidents.length, 1);
    expect(AppData.pendingResidents.first['name'], 'Rohan Mehta');
    expect(AppData.pendingResidents.first['status'], 'Pending Approval');

    // Assign resident
    final err = AppData.assignResidentToRoom(
      '101',
      'Rohan Mehta',
      phone: '9876543290',
      rent: 8500,
      dueDate: '10 Nov 2026',
    );

    expect(err, isNull);
    // Removed from pendingResidents
    expect(AppData.pendingResidents.any((r) => r['name'] == 'Rohan Mehta'), isFalse);

    // Updated in residents list
    final resident = AppData.residents.firstWhere((r) => r['name'] == 'Rohan Mehta');
    expect(resident['status'], 'Active');
    expect(resident['room'], '101');
    expect(resident['rent'], 8500);
    expect(resident['due_date'], '10 Nov 2026');
  });

  testWidgets('PendingApprovalsCard renders with yellow background, orange border, and Review & Assign button', (WidgetTester tester) async {
    bool reviewClicked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingApprovalsCard(
            pendingResidents: AppData.pendingResidents,
            onReviewAndAssign: () {
              reviewClicked = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Pending Resident Approvals'), findsOneWidget);
    expect(find.text('1 PENDING'), findsOneWidget);
    expect(find.text('Review & Assign'), findsOneWidget);

    // Verify styling: yellow background & orange border
    final container = tester.widget<Container>(find.byType(Container).first);
    final boxDecoration = container.decoration as BoxDecoration;
    expect(boxDecoration.color, const Color(0xFFFEF9C3));
    expect((boxDecoration.border as Border).top.color, const Color(0xFFF97316));

    // Tap Review & Assign
    await tester.tap(find.text('Review & Assign'));
    await tester.pumpAndSettle();
    expect(reviewClicked, isTrue);
  });

  testWidgets('DashboardScreen renders PendingApprovalsCard and opens Assign Room & Rent dialog', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify PendingApprovalsCard is displayed
    expect(find.byType(PendingApprovalsCard), findsOneWidget);
    expect(find.text('Pending Resident Approvals'), findsWidgets);
    expect(find.text('Review & Assign'), findsOneWidget);

    // Click Review & Assign
    await tester.tap(find.text('Review & Assign'));
    await tester.pumpAndSettle();

    // Verify AlertDialog titled 'Assign Room & Rent'
    expect(find.text('Assign Room & Rent'), findsOneWidget);
    expect(find.text('Rohan Mehta'), findsWidgets);
    expect(find.text('+91 9876543290'), findsWidgets);
    expect(find.text('Room Number *'), findsOneWidget);
    expect(find.text('Monthly Rent (₹) *'), findsOneWidget);
    expect(find.text('Payment Due Date *'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.text('Confirm & Assign'), findsOneWidget);

    // Tap Confirm & Assign
    await tester.tap(find.text('Confirm & Assign'));
    await tester.pumpAndSettle();

    // Dialog is closed, resident assigned
    expect(find.text('Assign Room & Rent'), findsNothing);
    expect(AppData.pendingResidents.isEmpty, isTrue);
    expect(find.byType(PendingApprovalsCard), findsNothing);
  });

  testWidgets('DashboardScreen Assign Room & Rent dialog allows rejecting with reason', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppData.pendingResidents = [
      {'name': 'Suresh Kumar', 'phone': '9876543291', 'status': 'Pending Approval'},
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review & Assign'), findsOneWidget);
    await tester.tap(find.text('Review & Assign'));
    await tester.pumpAndSettle();

    // Verify Reject Application button exists
    final rejectButton = find.text('Reject Application');
    expect(rejectButton, findsOneWidget);

    await tester.tap(rejectButton);
    await tester.pumpAndSettle();

    // Verify rejection dialog
    expect(find.text('Reject Registration'), findsOneWidget);
    expect(find.text('Confirm Rejection'), findsOneWidget);

    // Tap confirm rejection without reason
    await tester.tap(find.text('Confirm Rejection'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid rejection reason.'), findsOneWidget);

    // Enter reason
    await tester.enterText(find.byType(TextField).last, 'Incomplete Aadhaar card document');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm Rejection'));
    await tester.pumpAndSettle();

    // Application is removed
    expect(find.text('Reject Registration'), findsNothing);
    expect(find.text('Assign Room & Rent'), findsNothing);
  });
}
