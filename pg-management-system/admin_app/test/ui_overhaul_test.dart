import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_app/features/rooms_beds/rooms_beds_screen.dart';
import 'package:admin_app/features/residents/residents_screen.dart';
import 'package:admin_app/features/expenses/expenses_screen.dart';
import 'package:admin_app/features/properties/properties_screen.dart';
import 'package:admin_app/features/payments/payments_screen.dart';
import 'package:admin_app/features/staff/staff_screen.dart';
import 'package:admin_app/features/complaints/complaints_screen.dart';
import 'package:admin_app/features/leads/leads_screen.dart';
import 'package:admin_app/features/reports/reports_screen.dart';
import 'package:admin_app/features/dashboard/dashboard_screen.dart';
import 'package:admin_app/core/data/app_data.dart';

void main() {
  testWidgets('Room Cards show Edit icon and opens Manage Room modal with Delete Room confirmation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoomsBedsScreen())));
    await tester.pumpAndSettle();

    // Check Room 101 exists
    expect(find.text('Room 101'), findsOneWidget);

    // Verify Edit icon exists in Room Card
    final editIcons = find.byIcon(Icons.edit_outlined);
    expect(editIcons, findsWidgets);

    // Tap first Edit icon to open 'Manage Room' modal
    await tester.tap(editIcons.first);
    await tester.pumpAndSettle();

    // Verify Manage Room modal opens
    expect(find.text('Manage Room 101'), findsOneWidget);
    expect(find.text('Room 101'), findsWidgets);
    expect(find.text('Floor'), findsOneWidget);
    expect(find.text('Sharing Type'), findsOneWidget);

    // Verify red Delete Room button
    final deleteRoomBtn = find.widgetWithText(ElevatedButton, 'Delete Room');
    expect(deleteRoomBtn, findsOneWidget);

    // Click Delete Room button
    await tester.tap(deleteRoomBtn);
    await tester.pumpAndSettle();

    // Verify Confirmation Dialog with exact prompt text
    expect(find.text('Are you sure? This will remove all bed data'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Click Delete Room in confirmation
    final confirmBtn = find.widgetWithText(ElevatedButton, 'Delete Room').last;
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    // Room 101 is now removed
    expect(find.text('Manage Room 101'), findsNothing);
    expect(AppData.rooms.any((r) => r['number'] == '101'), isFalse);
  });

  testWidgets('Room Card matches reference design with centered beds and 2-column metrics', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoomsBedsScreen())));
    await tester.pumpAndSettle();

    // Room 102 should exist
    expect(find.text('Room 102'), findsOneWidget);

    // Bed icons in outline style
    expect(find.byIcon(Icons.bed_outlined), findsWidgets);

    // 2-column Occupied and Vacant labels exist in Room Card
    expect(find.text('Occupied'), findsWidgets);
    expect(find.text('Vacant'), findsWidgets);
  });

  testWidgets('Subtitles are removed across all admin app screens', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Properties screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PropertiesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Manage Properties'), findsOneWidget);
    expect(find.text('Real-time overview of your PG locations, rooms, and occupancy'), findsNothing);

    // Rooms & Beds screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoomsBedsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Rooms & Beds'), findsOneWidget);
    expect(find.text('Manage room availability and bed assignments'), findsNothing);

    // Residents screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ResidentsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Residents & KYC'), findsOneWidget);
    expect(find.text('Manage profiles, documents, and room assignments'), findsNothing);

    // Payments screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PaymentsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Rent & Payments'), findsOneWidget);
    expect(find.text('Track rent collections, pending dues, and payment receipts'), findsNothing);

    // Expenses screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExpensesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Expenses & Salaries'), findsOneWidget);
    expect(find.text('Track operational overheads, utilities, and staff salaries'), findsNothing);

    // Staff screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StaffScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Staff Management'), findsOneWidget);
    expect(find.text('Manage wardens, maintenance crew, and security personnel'), findsNothing);

    // Complaints screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ComplaintsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Complaints & Service Requests'), findsOneWidget);
    expect(find.text('Track, prioritize, and resolve resident service tickets'), findsNothing);
    expect(find.text('All Priorities'), findsOneWidget);
    expect(find.text('All Categories'), findsNothing);

    // Leads screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LeadsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Leads & Enquiries'), findsOneWidget);
    expect(find.text('Convert prospects into active residents across multiple channels'), findsNothing);

    // Reports screen
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ReportsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Reports & Analytics'), findsOneWidget);
    expect(find.text('Executive performance summaries and audit export statements'), findsNothing);
  });

  testWidgets('Add Room modal uses styled Form Dropdowns for Floor and Room Type', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoomsBedsScreen())));
    await tester.pumpAndSettle();

    // Tap Add Room button in header
    final addRoomBtn = find.text('Add Room');
    expect(addRoomBtn, findsOneWidget);
    await tester.tap(addRoomBtn);
    await tester.pumpAndSettle();

    // Verify Add New Room dialog opened
    expect(find.text('Add New Room'), findsOneWidget);

    // Verify Form Dropdowns exist for Select Floor and Room Type
    expect(find.widgetWithText(DropdownButtonFormField<String>, '1st Floor'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, '2-Sharing'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Residents Screen Add Resident modal uses Form Dropdown and successfully onboards', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ResidentsScreen())));
    await tester.pumpAndSettle();

    final addResidentBtn = find.text('Add Resident');
    expect(addResidentBtn, findsOneWidget);
    await tester.tap(addResidentBtn);
    await tester.pumpAndSettle();

    expect(find.text('Onboard New Resident'), findsOneWidget);

    // Verify Gender Form Dropdown
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Male'), findsOneWidget);

    // Verify Floor Number field exists in Stay Info
    expect(find.widgetWithText(TextField, 'Floor Number'), findsOneWidget);

    // Fill details
    await tester.enterText(find.widgetWithText(TextField, 'Full Name *'), 'Ananya Verma');
    await tester.enterText(find.widgetWithText(TextField, 'Phone Number *'), '9123456789');
    await tester.enterText(find.widgetWithText(TextField, 'Room Number *'), '102');

    // Tap onboard
    await tester.tap(find.text('Onboard Resident'));
    await tester.pumpAndSettle();

    // Ananya Verma should now be in the list
    expect(find.text('Ananya Verma'), findsOneWidget);
  });

  testWidgets('Add Expense modal uses styled Form Dropdowns', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExpensesScreen())));
    await tester.pumpAndSettle();

    final addExpenseBtn = find.widgetWithText(ElevatedButton, 'Add Expense');
    expect(addExpenseBtn, findsOneWidget);
    await tester.tap(addExpenseBtn);
    await tester.pumpAndSettle();

    expect(find.text('Add New Expense'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Utilities'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Leads Screen Edit Status button opens Update Lead Status dialog and updates status', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LeadsScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Leads & Enquiries'), findsOneWidget);
    expect(find.text('Rahul Sharma'), findsOneWidget);

    // Find the Edit Status button for the first lead
    final editStatusBtns = find.byTooltip('Edit Status');
    expect(editStatusBtns, findsWidgets);

    await tester.tap(editStatusBtns.first);
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.text('Update Lead Status'), findsOneWidget);
    expect(find.text('Prospect: Rahul Sharma • 9876500001'), findsOneWidget);
    expect(find.text('Pipeline Status *'), findsOneWidget);
    // Remarks/Notes should be removed
    expect(find.text('Follow-up Remarks / Notes'), findsNothing);

    // Save status
    await tester.tap(find.text('Save Status'));
    await tester.pumpAndSettle();

    expect(find.text('Update Lead Status'), findsNothing);
  });

  testWidgets('Staff Screen Edit button opens pre-filled Edit Staff dialog and saves changes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StaffScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Staff Management'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);

    // Find and tap Edit Staff button
    final editStaffBtns = find.byTooltip('Edit Staff');
    expect(editStaffBtns, findsWidgets);
    await tester.tap(editStaffBtns.first);
    await tester.pumpAndSettle();

    // Verify dialog opened with pre-filled details
    expect(find.text('Edit Staff Details'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Full Name *'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsWidgets);
    expect(find.text('Warden'), findsWidgets);
    expect(find.text('9876543210'), findsWidgets);
    expect(find.text('25000'), findsWidgets);

    // Verify Delete and Save Changes buttons exist
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // Save changes
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Staff Details'), findsNothing);
  });

  testWidgets('Leads Screen Add Lead dialog includes Status dropdown', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LeadsScreen())));
    await tester.pumpAndSettle();

    final addLeadBtn = find.text('Add Lead');
    expect(addLeadBtn, findsOneWidget);
    await tester.tap(addLeadBtn);
    await tester.pumpAndSettle();

    expect(find.text('Add New Lead'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Status'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Staff and Leads persist across tab rebuilds', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 1. Mount StaffScreen and add a new staff member to AppData
    AppData.staff.insert(0, {
      'name': 'Kavita Rao',
      'role': 'Manager',
      'phone': '9876543299',
      'salary': '30000',
      'status': 'Active',
    });

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StaffScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Kavita Rao'), findsOneWidget);

    // 2. Simulate navigating away (unmount StaffScreen, mount LeadsScreen)
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LeadsScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Leads & Enquiries'), findsOneWidget);

    // 3. Return to StaffScreen and verify persisted staff member
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StaffScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Kavita Rao'), findsOneWidget);

    // Clean up
    AppData.staff.removeWhere((s) => s['name'] == 'Kavita Rao');
  });

  testWidgets('Dashboard Room Availability card opens modal with Floor and vacant beds info', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    if (!AppData.rooms.any((r) => r['number'] == '101')) {
      AppData.rooms.insert(0, {
        'number': '101',
        'floor': 'Ground Floor',
        'type': '3-Sharing',
        'beds': [
          {'name': 'Bed A', 'status': 'Occupied', 'occupant': 'Test User'},
          {'name': 'Bed B', 'status': 'Available'},
        ],
      });
    }

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DashboardScreen())));
    await tester.pumpAndSettle();

    final roomAvailCard = find.text('Room Availability');
    expect(roomAvailCard, findsWidgets);

    // Tap on the Room Availability card
    await tester.tap(roomAvailCard.first);
    await tester.pumpAndSettle();

    // Verify modal appears as a Dialog with 2-column grid
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Ground Floor'), findsWidgets);
    expect(find.text('1st Floor'), findsWidgets);
    expect(find.textContaining('Available'), findsWidgets);

    // Close modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });
}
