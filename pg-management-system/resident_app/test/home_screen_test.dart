import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/network/token_storage.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/core/widgets/main_layout.dart';
import 'package:resident_app/features/home/home_screen.dart';

void main() {
  testWidgets(
    'HomeScreen renders redesigned Header, Hero Rent & Stay Card, Notices, and Complaint Status (Light & Dark)',
    (WidgetTester tester) async {
      AppData.currentResident =
          AppData.residents[1]; // Priya Sharma (Active, Room 101)

      for (final width in [360.0, 375.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        // Light Theme check
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const MainLayout(child: HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.text('Priya Sharma'), findsOneWidget);
        expect(find.text('PS'), findsOneWidget);
        // Notification bell completely removed from header
        expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);

        // Verify pure white background in Light Theme
        final homeScaffold = tester.widget<Scaffold>(
          find.descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scaffold),
          ),
        );
        expect(homeScaffold.backgroundColor, const Color(0xFFFFFFFF));

        // Hero Rent & Stay section focused purely on rent details (NO action buttons)
        expect(find.text('8,000'), findsWidgets);
        expect(find.text('Pay now'), findsNothing);
        expect(find.text('View receipt'), findsNothing);
        expect(find.text('BNR Luxury PG'), findsOneWidget);
        expect(find.text('Room 101'), findsOneWidget);
        expect(find.text('Floor'), findsOneWidget);
        expect(find.text('1st'), findsOneWidget);
        expect(find.text('Resident since'), findsOneWidget);
        expect(find.text('01 Oct 2026'), findsOneWidget);

        // Notices section
        expect(find.text('Notices'), findsOneWidget);

        // Complaint Status section replaces Today's Dinner
        expect(find.text('Complaint Status'), findsOneWidget);
        expect(find.textContaining("Today's Dinner"), findsNothing);

        // Recent payments section completely removed
        expect(find.text('Recent payments'), findsNothing);

        // Bottom navigation bar
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Payments'), findsOneWidget);
        expect(find.text('Food'), findsOneWidget);
        expect(find.text('Menu'), findsOneWidget);
        expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

        // Dark Theme check
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: const MainLayout(child: HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Priya Sharma'), findsOneWidget);
        expect(find.text('Pay now'), findsNothing);
      }

      tester.view.resetPhysicalSize();
    },
  );

  testWidgets(
    'HomeScreen displays Pending state for unassigned resident and shows Complaint Status',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppData.currentResident =
          AppData.residents.first; // Rohan Mehta (Pending)

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rohan Mehta'), findsOneWidget);
      expect(find.text('RM'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Room Pending'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Recent payments'), findsNothing);
      expect(find.text('Complaint Status'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen respects reduced motion accessibility setting without issues',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppData.currentResident = AppData.residents[1];

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MainLayout(child: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Complaint Status'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen Paid status renders Paid chip and preserves navigation routes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppData.currentResident = {
        ...AppData.residents[1],
        'rent_status': 'Paid',
      };

      final visitedRoutes = <String>[];

      final testRouter = GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            builder: (context, state, child) => MainLayout(child: child),
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/payments',
                builder: (context, state) {
                  visitedRoutes.add('/payments');
                  return const Scaffold(
                    body: Center(child: Text('Payments Page')),
                  );
                },
              ),
              GoRoute(
                path: '/food-menu',
                builder: (context, state) {
                  visitedRoutes.add('/food-menu');
                  return const Scaffold(body: Center(child: Text('Food Page')));
                },
              ),
              GoRoute(
                path: '/menu',
                builder: (context, state) {
                  visitedRoutes.add('/menu');
                  return const Scaffold(
                    body: Center(child: Text('Profile Menu Page')),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/notices',
            builder: (context, state) {
              visitedRoutes.add('/notices');
              return const Scaffold(body: Center(child: Text('Notices Page')));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: testRouter,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('View receipt'), findsNothing);

      // Verify Notices navigation
      await tester.tap(find.text('Property Announcements'));
      await tester.pumpAndSettle();
      expect(visitedRoutes.contains('/notices'), isTrue);

      // Go back to Home via bottom nav
      testRouter.go('/home');
      await tester.pumpAndSettle();

      // Verify Payments bottom nav item
      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();
      expect(visitedRoutes.contains('/payments'), isTrue);

      // Go back to Home and test Food bottom nav item
      testRouter.go('/home');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      expect(visitedRoutes.contains('/food-menu'), isTrue);

      // Verify Menu bottom nav item
      testRouter.go('/home');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(visitedRoutes.contains('/menu'), isTrue);
    },
  );

  testWidgets(
    'HomeScreen parses nested getProfile response (resident_info & stay_details)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppData.currentResident = {
        'resident_info': {'full_name': 'Aarav Patel', 'status': 'ACTIVE'},
        'stay_details': {
          'property_name': 'Origin Luxury PG',
          'room_number': '204',
          'floor_number': 2,
          'living_since': '2026-09-01',
          'monthly_rent': 9500.0,
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MainLayout(child: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aarav Patel'), findsOneWidget);
      expect(find.text('AP'), findsOneWidget);
      expect(find.text('Origin Luxury PG'), findsOneWidget);
      expect(find.text('Room 204'), findsOneWidget);
      expect(find.text('2nd'), findsOneWidget);
      expect(find.text('01 Sep 2026'), findsOneWidget);
      expect(find.text('9,500'), findsWidgets);
      expect(find.text('Pay now'), findsNothing);
    },
  );

  testWidgets(
    'HomeScreen prefers saved TokenStorage.residentProfile over unassigned Pending placeholder',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      await TokenStorage.init();
      await TokenStorage.saveResidentProfile({
        'full_name': 'Aarav Patel',
        'stay_details': {
          'property_name': 'Origin Luxury PG',
          'room_number': '204',
          'floor_number': 2,
          'living_since': '2026-09-01',
          'monthly_rent': 9500.0,
        },
      });
      addTearDown(() async {
        await TokenStorage.clear();
        AppData.currentResident = AppData.residents[1];
      });

      // Simulate uninitialized startup fallback in memory
      AppData.currentResident = AppData.residents.first;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MainLayout(child: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aarav Patel'), findsOneWidget);
      expect(find.text('Room 204'), findsOneWidget);
      expect(find.text('Room Pending'), findsNothing);
      expect(find.text('9,500'), findsWidgets);
      expect(find.text('Pay now'), findsNothing);
    },
  );

  testWidgets(
    'HomeScreen renders Rent Payment Warning card exactly when due in <= 2 days',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final twoDaysLater = now.add(const Duration(days: 2));
      final dueDateStr =
          '${twoDaysLater.year}-${twoDaysLater.month.toString().padLeft(2, '0')}-${twoDaysLater.day.toString().padLeft(2, '0')}';

      AppData.currentResident = {
        ...AppData.residents[1],
        'rent_status': 'Unpaid',
        'due_date': dueDateStr,
        'amount': 8000,
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MainLayout(child: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the warning card is displayed
      expect(find.textContaining('Rent payment due in 2 days'), findsOneWidget);
      expect(
        find.textContaining('Upcoming rent payment is due on'),
        findsOneWidget,
      );
    },
  );
}
