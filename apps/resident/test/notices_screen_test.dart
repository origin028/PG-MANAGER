import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/notices/notices_screen.dart';

const _sampleNotices = [
  {
    'id': 'NOTIF-1',
    'title': 'Water supply maintenance',
    'description': 'Water will be off tomorrow from 10:00 AM to 2:00 PM for solar pipeline servicing.',
    'category': 'Facility',
    'date': 'Today, 10:00 AM',
    'icon': Icons.water_drop_rounded,
    'isImportant': true,
  },
  {
    'id': 'NOTIF-3',
    'title': 'High-Speed Wi-Fi Upgrade',
    'description': 'Mesh router firmware across Floor 1 and Floor 2 has been upgraded to 300 Mbps bandwidth.',
    'category': 'Internet',
    'date': '24 Oct 2026',
    'icon': Icons.wifi_rounded,
    'isImportant': false,
  },
  {
    'id': 'NOTIF-4',
    'title': 'Visitor Timing Reminder',
    'description': 'Visitors and guests are allowed in the common lounge area until 9:00 PM daily.',
    'category': 'Rules',
    'date': '20 Oct 2026',
    'icon': Icons.schedule_rounded,
    'isImportant': false,
  },
  {
    'id': 'NOTIF-5',
    'title': 'Scheduled Pest Control Drive',
    'description': 'Bi-monthly pest control and deep cleaning will be conducted this Sunday from 11:00 AM.',
    'category': 'Maintenance',
    'date': '18 Oct 2026',
    'icon': Icons.cleaning_services_rounded,
    'isImportant': false,
  },
];

void main() {
  testWidgets(
    'NoticesScreen renders Light & Dark themes across narrow and mobile viewports without overflow and without payment UI',
    (WidgetTester tester) async {
      for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        // Light Theme verification
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const NoticesScreen(initialNotices: _sampleNotices),
          ),
        );
        await tester.pumpAndSettle();

        final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

        expect(find.text('Notices & Circulars'), findsOneWidget);
        expect(find.text('TODAY'), findsOneWidget);
        expect(find.text('EARLIER'), findsOneWidget);
        expect(find.text('Water supply maintenance'), findsOneWidget);
        expect(find.text('High-Speed Wi-Fi Upgrade'), findsOneWidget);
        expect(find.text('Visitor Timing Reminder'), findsOneWidget);
        expect(find.text('Scheduled Pest Control Drive'), findsOneWidget);
        expect(find.text('Important'), findsOneWidget);
        expect(find.text('Facility'), findsOneWidget);

        // Strict check: NO payment UI or rent due CTA
        expect(find.text('Pay now'), findsNothing);
        expect(find.text('Pay Now'), findsNothing);
        expect(find.text('Pay rent now'), findsNothing);
        expect(find.text('Monthly Rent Due Reminder'), findsNothing);
        expect(find.text('RENT DUE AMOUNT'), findsNothing);

        // Dark Theme verification
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: const NoticesScreen(initialNotices: _sampleNotices),
          ),
        );
        await tester.pumpAndSettle();

        final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
        expect(find.text('Notices & Circulars'), findsOneWidget);
        expect(find.text('Water supply maintenance'), findsOneWidget);
        expect(find.text('Pay now'), findsNothing);
      }

      addTearDown(() => tester.view.resetPhysicalSize());
    },
  );

  testWidgets(
    'NoticesScreen supports Empty State and Refresh Announcements recovery',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const NoticesScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Announcements Yet'), findsOneWidget);
      expect(
        find.text(
          'No notices or announcements have been published for your property.',
        ),
        findsOneWidget,
      );
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Water supply maintenance'), findsNothing);
    },
  );

  testWidgets(
    'NoticesScreen Back button preserves GoRouter pop/home navigation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = GoRouter(
        initialLocation: '/notices',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Home Destination'))),
          ),
          GoRoute(
            path: '/notices',
            builder: (context, state) =>
                const NoticesScreen(initialNotices: _sampleNotices),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Home Destination'), findsOneWidget);
    },
  );

  testWidgets('NoticesScreen honors reduced motion accessibility setting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: NoticesScreen(initialNotices: _sampleNotices),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Notices & Circulars'), findsOneWidget);
    expect(find.text('Water supply maintenance'), findsOneWidget);
  });
}
