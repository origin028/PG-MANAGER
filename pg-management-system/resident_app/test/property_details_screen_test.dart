import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:resident_app/core/data/app_data.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/profile/property_details_screen.dart';

void main() {
  late Map<String, dynamic> originalResident;

  setUp(() {
    originalResident = Map<String, dynamic>.from(AppData.currentResident);
  });

  tearDown(() {
    AppData.currentResident = originalResident;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'PropertyDetailsScreen renders Light & Dark themes across narrow and mobile viewports without overflow',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1], // Priya Sharma, Room 101, Bed B
    };

    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;

      // Light theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('prop_light_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const PropertyDetailsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, const Color(0xFFFFFFFF));

      expect(find.text('Property Details'), findsOneWidget);
      expect(find.text('CO-LIVING PG'), findsOneWidget);
      expect(find.text('BNR Luxury PG'), findsOneWidget);
      expect(find.text('Koramangala 6th Block, Bengaluru'), findsOneWidget);
      expect(find.text('Verified PG'), findsOneWidget);
      expect(find.text('Room Number'), findsOneWidget);
      expect(find.text('101 · B'), findsOneWidget);
      expect(find.text('Floor'), findsOneWidget);
      expect(find.text('1st Floor'), findsOneWidget);
      expect(find.text('Full Property Address'), findsOneWidget);
      expect(find.byTooltip('Copy Address'), findsOneWidget);
      expect(
        find.text('Tap to copy full address for delivery or visitors'),
        findsOneWidget,
      );
      expect(find.text('AMENITIES & INCLUSIONS'), findsOneWidget);
      expect(find.text('High Speed Wi-Fi'), findsOneWidget);
      expect(find.text('3 Times Daily Meals'), findsOneWidget);

      // Dark theme
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('prop_dark_$width'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const PropertyDetailsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, const Color(0xFF1B232A));
      expect(find.text('Property Details'), findsOneWidget);
      expect(find.text('BNR Luxury PG'), findsOneWidget);
    }

    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
  });

  testWidgets(
      'PropertyDetailsScreen copies full address via both Copy buttons and shows confirmation',
      (WidgetTester tester) async {
    AppData.currentResident = {
      ...AppData.residents[1],
    };

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        copiedText = args?['text']?.toString();
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const PropertyDetailsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap top-right icon button
    await tester.tap(find.byTooltip('Copy Address'));
    await tester.pumpAndSettle();

    expect(
      copiedText,
      '#124, 5th Cross, 6th Block, Near Sony World Signal, Koramangala, Bengaluru, Karnataka - 560095',
    );
    expect(find.text('Address copied to clipboard!'), findsOneWidget);

    // Dismiss snackbar and test bottom copy helper strip
    ScaffoldMessenger.of(
      tester.element(find.byType(PropertyDetailsScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    copiedText = null;
    await tester.tap(
      find.text('Tap to copy full address for delivery or visitors'),
    );
    await tester.pumpAndSettle();

    expect(
      copiedText,
      '#124, 5th Cross, 6th Block, Near Sony World Signal, Koramangala, Bengaluru, Karnataka - 560095',
    );
    expect(find.text('Address copied to clipboard!'), findsOneWidget);
  });

  testWidgets(
      'PropertyDetailsScreen dynamically maps resident property, room ordinal floor, reduced motion, and GoRouter back',
      (WidgetTester tester) async {
    AppData.currentResident = {
      'name': 'Riya Nair',
      'phone': '9876543219',
      'property_name': 'Skyline Girls PG',
      'room_number': '308',
      'bed': 'Bed A',
    };

    final router = GoRouter(
      initialLocation: '/menu',
      routes: [
        GoRoute(
          path: '/menu',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/property-details'),
                child: const Text('Go Property'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/property-details',
          builder: (context, state) => const PropertyDetailsScreen(),
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

    await tester.tap(find.text('Go Property'));
    await tester.pumpAndSettle();

    expect(find.text('GIRLS PG'), findsOneWidget);
    expect(find.text('Skyline Girls PG'), findsOneWidget);
    expect(find.text('HSR Layout Sector 2, 14th Main'), findsOneWidget);
    expect(find.text('308 · A'), findsOneWidget);
    expect(find.text('3rd Floor'), findsOneWidget);
    expect(find.text('Common Lounge & TV'), findsOneWidget);

    // Offline cached warning banner when API cannot connect in tests
    expect(
      find.text('Displaying cached property details (offline).'),
      findsOneWidget,
    );

    // Refresh button works cleanly
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Skyline Girls PG'), findsOneWidget);

    // Back button pops cleanly back to /menu
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Go Property'), findsOneWidget);
  });
}

