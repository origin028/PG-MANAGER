import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/features/profile/menu_screen.dart';
import 'package:resident_app/features/profile/property_details_screen.dart';
import 'package:resident_app/features/complaints/raise_complaint_screen.dart';
import 'package:resident_app/features/profile/call_management_screen.dart';
import 'package:resident_app/features/profile/settings_screen.dart';
import 'package:resident_app/features/profile/profile_screen.dart';
import 'package:resident_app/features/profile/rent_deposit_screen.dart';
import 'package:resident_app/features/complaints/all_complaints_screen.dart';

void main() {
  testWidgets('MenuScreen displays resident profile card and menu items without duplicate My Profile row', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Menu'), findsNothing);
    expect(find.text('My Profile'), findsNothing);
    expect(find.text('Rent & Deposit Details'), findsOneWidget);
    expect(find.text('Property Details'), findsOneWidget);
    expect(find.text('Raise Complaint'), findsOneWidget);
    expect(find.text('Call Management'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('PropertyDetailsScreen displays property info and copy address button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: PropertyDetailsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Property Details'), findsOneWidget);
    expect(find.text('BNR Luxury PG'), findsOneWidget);
    expect(find.text('Room Number'), findsOneWidget);
    expect(find.text('Floor'), findsOneWidget);
    expect(find.text('Full Property Address'), findsOneWidget);
    expect(find.byTooltip('Copy Address'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsWidgets);
  });

  testWidgets('RaiseComplaintScreen displays category dropdown, description, and upload photo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: RaiseComplaintScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Raise Complaint'), findsOneWidget);
    expect(find.text('Complaint Category *'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Issue Description *'), findsOneWidget);
    expect(find.text('Upload Photo'), findsOneWidget);
    expect(find.text('Submit Complaint'), findsOneWidget);
  });

  testWidgets('CallManagementScreen displays manager phone, WhatsApp and caretaker', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: CallManagementScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Call Management'), findsOneWidget);
    expect(find.text('Property Owner'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsWidgets);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Gate Security & Caretaker'), findsOneWidget);
  });

  testWidgets('SettingsScreen displays Dark Mode switch, Language dropdown, Push Notifications, and red Logout button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('App Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Push Notifications'), findsOneWidget);
    expect(find.text('Rent Reminders'), findsOneWidget);
    expect(find.text('Maintenance Alerts'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.text('Account Details'), findsNothing);
    expect(find.text('PG Pilot Resident App • Version 1.0.0 (Build 2026)'), findsNothing);
  });

  testWidgets('AllComplaintsScreen displays complaint history, resolved badge, admin note, and clear all dialog', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: AllComplaintsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Complaint History'), findsOneWidget);
    expect(find.text('Clear All'), findsOneWidget);
    expect(find.text('AC not cooling'), findsOneWidget);
    expect(find.text('Resolved'), findsWidgets);
    expect(find.textContaining('Gas refilled by technician'), findsOneWidget);

    // Tap Clear All
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();

    expect(find.text('Clear Complaint History'), findsOneWidget);
    expect(find.text('Are you sure you want to clear your complaint history?'), findsOneWidget);

    // Confirm clear all
    final clearBtn = find.widgetWithText(ElevatedButton, 'Clear All');
    await tester.tap(clearBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No complaints found'), findsOneWidget);
  });

  testWidgets('ProfileScreen displays Edit Profile button and camera icon badge for selfie', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    expect(find.text('Personal & Contact Details'), findsOneWidget);
    expect(find.text('KYC & Identity Verification'), findsOneWidget);
  });

  testWidgets('RentDepositScreen displays Security Deposit and Fixed Rent inside card', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: RentDepositScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Rent & Deposit Details'), findsOneWidget);
    expect(find.text('Security Deposit'), findsOneWidget);
    expect(find.text('TOTAL DEPOSIT'), findsOneWidget);
    expect(find.text('50% Refundable'), findsOneWidget);
    expect(find.text('Active & Secure'), findsOneWidget);
    expect(find.text('Fixed Rent'), findsOneWidget);
    expect(find.textContaining('8000 / month'), findsOneWidget);
    expect(find.text('This Month Rent'), findsNothing);
    expect(find.text('Rent Payment History'), findsNothing);
  });
}
