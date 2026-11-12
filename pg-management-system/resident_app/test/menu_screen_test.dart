import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/core/widgets/main_layout.dart';
import 'package:resident_app/features/profile/menu_screen.dart';

void main() {
  testWidgets(
      'MenuScreen renders Light & Dark themes across narrow and mobile viewports without overflow',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1], // Priya Sharma, Room 101
      'rent_status': 'Unpaid',
    };

    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light Theme verification
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('menu_light_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const MainLayout(child: MenuScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(MenuScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('Menu'), findsOneWidget); // Bottom Nav tab only (no page heading)
      expect(find.text('My Profile'), findsNothing);
      expect(find.text('PS'), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Room 101 · +91 9876543210'), findsOneWidget);
      expect(find.text('SERVICES & MANAGEMENT'), findsOneWidget);
      expect(find.text('HELP & SUPPORT'), findsOneWidget);
      expect(find.text('ACCOUNT SETTINGS'), findsOneWidget);
      expect(find.text('Rent & Deposit Details'), findsOneWidget);
      expect(find.text('1 due'), findsOneWidget);
      expect(find.text('Property Details'), findsOneWidget);
      expect(find.text('Raise Complaint'), findsOneWidget);
      expect(find.text('Call Management'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Dark Theme verification
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('menu_dark_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const MainLayout(child: MenuScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(MenuScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Rent & Deposit Details'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
  });

  testWidgets('MenuScreen hides due badge when rent is Paid and supports nested profile',
      (WidgetTester tester) async {
    AppData.currentResident = {
      'resident_info': {
        'full_name': 'Aarav Patel',
        'phone': '+91 9898989898',
      },
      'stay_details': {
        'room_number': '305',
      },
      'rent_status': 'Paid',
    };
    addTearDown(() => AppData.currentResident = AppData.residents[1]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MenuScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AP'), findsOneWidget);
    expect(find.text('Aarav Patel'), findsOneWidget);
    expect(find.text('Room 305 · +91 9898989898'), findsOneWidget);
    expect(find.text('1 due'), findsNothing);
  });

  testWidgets('MenuScreen preserves all existing GoRouter navigation routes',
      (WidgetTester tester) async {
    AppData.currentResident = AppData.residents[1];
    final visited = <String>[];

    final router = GoRouter(
      initialLocation: '/menu',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainLayout(child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/payments', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/food-menu', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/menu', builder: (_, _) => const MenuScreen()),
          ],
        ),
        for (final path in [
          '/profile',
          '/rent-deposit',
          '/property-details',
          '/raise-complaint',
          '/call-management',
          '/settings',
        ])
          GoRoute(
            path: path,
            builder: (context, state) {
              visited.add(path);
              return Scaffold(body: Center(child: Text('Dest:$path')));
            },
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

    // Tap Hero profile card -> /profile
    await tester.tap(find.text('Priya Sharma'));
    await tester.pumpAndSettle();
    expect(visited.last, '/profile');
    router.pop();
    await tester.pumpAndSettle();

    final rowRoutes = <(String, String)>[
      ('Rent & Deposit Details', '/rent-deposit'),
      ('Property Details', '/property-details'),
      ('Raise Complaint', '/raise-complaint'),
      ('Call Management', '/call-management'),
      ('Settings', '/settings'),
    ];

    for (final (label, route) in rowRoutes) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(visited.last, route);
      router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('MenuScreen honors reduced motion accessibility setting',
      (WidgetTester tester) async {
    AppData.currentResident = AppData.residents[1];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MenuScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Menu'), findsNothing);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}

