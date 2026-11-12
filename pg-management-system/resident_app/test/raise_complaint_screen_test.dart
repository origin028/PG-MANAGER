import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/complaints/raise_complaint_screen.dart';

void main() {
  late Map<String, dynamic> originalResident;
  late List<Map<String, dynamic>> originalComplaints;

  setUp(() {
    originalResident = Map<String, dynamic>.from(AppData.currentResident);
    originalComplaints = List<Map<String, dynamic>>.from(AppData.complaints);
  });

  tearDown(() {
    AppData.currentResident = originalResident;
    AppData.complaints = originalComplaints;
  });

  testWidgets(
      'RaiseComplaintScreen renders Light & Dark themes across narrow and mobile viewports without overflow',
      (WidgetTester tester) async {
    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('complaint_light_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const RaiseComplaintScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('Raise Complaint'), findsOneWidget);
      expect(find.text('Prompt maintenance support'), findsOneWidget);
      expect(find.text('Complaint Category *'), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Issue Description *'), findsOneWidget);
      expect(find.text('Photo Attachment (Optional)'), findsOneWidget);
      expect(find.text('Upload Photo'), findsOneWidget);
      expect(find.text('Submit Complaint'), findsOneWidget);
      expect(find.text('WHAT HAPPENS NEXT'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);

      // Dark theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('complaint_dark_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const RaiseComplaintScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Raise Complaint'), findsOneWidget);
      expect(find.text('Submit Complaint'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
  });

  testWidgets(
      'RaiseComplaintScreen supports category dropdown, description validation, photo attach/remove & complaint submission',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
    };

    final router = GoRouter(
      initialLocation: '/menu',
      routes: [
        GoRoute(
          path: '/menu',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/raise-complaint'),
                child: const Text('Go Complaint'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/raise-complaint',
          builder: (context, state) => const RaiseComplaintScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go Complaint'));
    await tester.pumpAndSettle();

    // 1. Validate empty & short description errors
    await tester.ensureVisible(find.text('Submit Complaint'));
    await tester.tap(find.text('Submit Complaint'));
    await tester.pumpAndSettle();
    expect(find.text('Please describe the issue in detail'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('Submit Complaint'));
    await tester.pumpAndSettle();
    expect(find.text('Please provide at least a few words'), findsOneWidget);

    // 2. Select another existing category from dropdown
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electrical').last);
    await tester.pumpAndSettle();
    expect(find.text('Electrical'), findsOneWidget);

    // 3. Attach and remove photo
    await tester.ensureVisible(find.text('Upload Photo'));
    await tester.tap(find.text('Upload Photo'));
    await tester.pumpAndSettle();
    expect(find.text('complaint_issue_photo.jpg'), findsOneWidget);
    expect(find.text('Sample photo attached successfully!'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove photo'));
    await tester.pumpAndSettle();
    expect(find.text('Upload Photo'), findsOneWidget);

    // Re-attach photo before submit
    await tester.tap(find.text('Upload Photo'));
    await tester.pumpAndSettle();
    expect(find.text('complaint_issue_photo.jpg'), findsOneWidget);

    // 4. Enter valid issue description and submit
    final initialCount = AppData.complaints.length;
    await tester.enterText(
      find.byType(TextFormField),
      'Tube light flickering near room entrance',
    );
    await tester.ensureVisible(find.text('Submit Complaint'));
    await tester.tap(find.text('Submit Complaint'));
    await tester.pumpAndSettle();

    expect(AppData.complaints.length, initialCount + 1);
    expect(AppData.complaints.first['category'], 'Electrical');
    expect(
      AppData.complaints.first['issue'],
      'Tube light flickering near room entrance',
    );
    expect(AppData.complaints.first['photo'], 'complaint_issue_photo.jpg');
    expect(AppData.complaints.first['status'], 'Open');
    expect(find.text('Go Complaint'), findsOneWidget);
  });

  testWidgets('RaiseComplaintScreen back button pops cleanly with GoRouter',
      (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/menu',
      routes: [
        GoRoute(
          path: '/menu',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/raise-complaint'),
                child: const Text('Go Complaint'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/raise-complaint',
          builder: (context, state) => const RaiseComplaintScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go Complaint'));
    await tester.pumpAndSettle();
    expect(find.text('Raise Complaint'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Go Complaint'), findsOneWidget);
  });
}

