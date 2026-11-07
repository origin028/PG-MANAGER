import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/features/home/home_screen.dart';

void main() {
  testWidgets('Resident App HomeScreen displays Stay Card, Notices Box, Payment Reminder, and Recent Payments', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // 1. Verify Quick Actions row is REMOVED
    expect(find.text('Quick Actions'), findsNothing);

    // 2. Verify Top Dark Stay Card
    expect(find.text('YOUR STAY'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets); // Status pill and pending room/floor
    expect(find.text('BNR Luxury PG'), findsOneWidget);
    expect(find.byIcon(Icons.bed_rounded), findsOneWidget);
    expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
    expect(find.textContaining('Living Since'), findsOneWidget);
    expect(find.text('Rent Status'), findsNothing);
    expect(find.textContaining('Due'), findsWidgets);

    // 3. Verify Notices Box (Single row with View all)
    expect(find.text('Notices'), findsWidgets);
    expect(find.text('View all'), findsWidgets);
    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);

    // Verify Complaint Updates Card (NEW)
    expect(find.text('Complaint Updates'), findsOneWidget);
    expect(find.textContaining('AC not cooling'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);

    // 4. Verify Payment Reminder card (Rent Due on [Date] - ₹[Amount])
    expect(find.textContaining('Rent Due on'), findsOneWidget);
    expect(find.text('Pay Now'), findsWidgets);

    // 5. Verify Recent Payments section is REMOVED
    expect(find.text('Recent Payments'), findsNothing);
  });

  testWidgets('Resident App HomeScreen displays Living pill for Active Resident', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Set currentResident to active resident (Priya Sharma)
    AppData.currentResident = AppData.residents[1];

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('YOUR STAY'), findsOneWidget);
    expect(find.text('Living'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
    expect(find.text('Floor 1st'), findsOneWidget);
    expect(find.text('BNR Luxury PG'), findsOneWidget);
    expect(find.text('Rent Status'), findsNothing);
  });
}
