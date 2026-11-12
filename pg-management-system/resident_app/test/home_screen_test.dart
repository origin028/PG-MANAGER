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
  testWidgets('HomeScreen renders redesigned Header, Hero Rent & Stay Card, Today, and Recent payments for Active Resident (Light & Dark)', (WidgetTester tester) async {
    AppData.currentResident = AppData.residents[1]; // Priya Sharma (Active, Room 101)

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
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // Verify pure white background in Light Theme
      final homeScaffold = tester.widget<Scaffold>(find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scaffold),
      ));
      expect(homeScaffold.backgroundColor, const Color(0xFFFFFFFF));

      // Hero Rent & Stay section
      expect(find.text('8,000'), findsWidgets);
      expect(find.text('Pay now'), findsOneWidget);
      expect(find.text('BNR Luxury PG'), findsOneWidget);
      expect(find.text('Room 101'), findsOneWidget);
      expect(find.text('Floor'), findsOneWidget);
      expect(find.text('1st'), findsOneWidget);
      expect(find.text('Resident since'), findsOneWidget);
      expect(find.text('01 Oct 2026'), findsOneWidget);

      // Today section (Notices + Today's Food)
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Notices'), findsOneWidget);
      expect(find.textContaining('Today\'s'), findsOneWidget);

      // Recent payments section
      expect(find.text('Recent payments'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);

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
      expect(find.text('Pay now'), findsOneWidget);
    }

    tester.view.resetPhysicalSize();
  });

  testWidgets('HomeScreen displays Pending state for unassigned resident and opens Notifications sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppData.currentResident = AppData.residents.first; // Rohan Mehta (Pending)

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rohan Mehta'), findsOneWidget);
    expect(find.text('RM'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Room Pending'), findsOneWidget);
    expect(find.text('Pay now'), findsOneWidget);
    expect(find.text('No payments recorded yet'), findsOneWidget);

    // Tap bell icon to verify Notifications sheet still opens cleanly
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Rent Due Reminder'), findsOneWidget);
  });

  testWidgets('HomeScreen respects reduced motion accessibility setting without issues', (WidgetTester tester) async {
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
    expect(find.text('Pay now'), findsOneWidget);
  });

  testWidgets('HomeScreen Paid status renders View receipt and preserves all existing routes', (WidgetTester tester) async {
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
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/payments',
              builder: (context, state) {
                visitedRoutes.add('/payments');
                return const Scaffold(body: Center(child: Text('Payments Page')));
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
                return const Scaffold(body: Center(child: Text('Profile Menu Page')));
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
        GoRoute(
          path: '/receipt',
          builder: (context, state) {
            visitedRoutes.add('/receipt');
            return const Scaffold(body: Center(child: Text('Receipt Page')));
          },
        ),
        GoRoute(
          path: '/property-details',
          builder: (context, state) {
            visitedRoutes.add('/property-details');
            return const Scaffold(body: Center(child: Text('Property Details Page')));
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
    expect(find.text('View receipt'), findsOneWidget);

    // Verify Notices navigation
    await tester.tap(find.text('Notices'));
    await tester.pumpAndSettle();
    expect(visitedRoutes.contains('/notices'), isTrue);

    // Go back to Home via bottom nav
    testRouter.go('/home');
    await tester.pumpAndSettle();

    // Verify Today's Food navigation
    await tester.tap(find.textContaining("Today's"));
    await tester.pumpAndSettle();
    expect(visitedRoutes.contains('/food-menu'), isTrue);

    // Verify Menu bottom nav item
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(visitedRoutes.contains('/menu'), isTrue);

    // Back to Home and test See all -> /payments
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(visitedRoutes.contains('/payments'), isTrue);

    // Back to Home and verify View receipt -> /receipt
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View receipt'));
    await tester.pumpAndSettle();
    expect(visitedRoutes.contains('/receipt'), isTrue);
  });

  testWidgets('HomeScreen Pay now navigates to existing /payments flow when unpaid', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppData.currentResident = {
      ...AppData.residents[1],
      'rent_status': 'Unpaid',
    };

    String? navigatedRoute;
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainLayout(child: child),
          routes: [
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/payments',
              builder: (context, state) {
                navigatedRoute = '/payments';
                return const Scaffold(body: Center(child: Text('Payments Route')));
              },
            ),
            GoRoute(path: '/food-menu', builder: (context, state) => const SizedBox()),
            GoRoute(path: '/menu', builder: (context, state) => const SizedBox()),
          ],
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

    await tester.tap(find.text('Pay now'));
    await tester.pumpAndSettle();
    expect(navigatedRoute, '/payments');
  });

  testWidgets('HomeScreen parses nested getProfile response (resident_info & stay_details) and shows Pay now', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppData.currentResident = {
      'resident_info': {
        'full_name': 'Aarav Patel',
        'status': 'ACTIVE',
      },
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
    expect(find.text('Pay now'), findsOneWidget);
  });

  testWidgets('HomeScreen prefers saved TokenStorage.residentProfile over unassigned Pending placeholder', (WidgetTester tester) async {
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
    expect(find.text('Pay now'), findsOneWidget);
  });
}
