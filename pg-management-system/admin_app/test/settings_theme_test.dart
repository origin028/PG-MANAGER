import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:admin_app/core/theme/app_theme.dart';
import 'package:admin_app/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsScreen renders all 5 cards and log out button correctly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: const Scaffold(body: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Page Title
    expect(find.text('Application Settings'), findsOneWidget);

    // 2. Verify Card 1: Account & Profile
    expect(find.text('Account & Profile'), findsOneWidget);
    expect(find.text('Manage your personal and business contact details.'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Owner Name'), findsOneWidget);
    expect(find.text('Owner Manager'), findsOneWidget);
    expect(find.text('Business / Company Name'), findsOneWidget);
    expect(find.text('Urban Stays & Co.'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('admin@pgmanager.com'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);

    // 3. Verify Card 2: Security
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Manage your password and account security.'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Account Password'), findsOneWidget);
    expect(find.text('Last changed: Never'), findsOneWidget);
    expect(find.text('Access key'), findsOneWidget);
    expect(find.text('Enter your unique access key'), findsOneWidget);
    expect(find.text('••••••••••••'), findsOneWidget);

    // Test Access Key Eye Toggle
    final eyeIcon = find.byTooltip('Show key');
    expect(eyeIcon, findsOneWidget);
    await tester.tap(eyeIcon);
    await tester.pumpAndSettle();
    expect(find.text('PG-ACC-9842-SEC-KEY'), findsOneWidget);

    // 4. Verify Card 3: General & Appearance
    expect(find.text('General & Appearance'), findsOneWidget);
    expect(find.text('Change the theme and language.'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Select your preferred color scheme'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Select your preferred application language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    // 5. Verify Card 4: Subscription Plan
    expect(find.text('Subscription Plan'), findsOneWidget);
    expect(find.text('Manage your PG Owner subscription.'), findsOneWidget);
    expect(find.text('Premium Plan'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('₹1,999'), findsOneWidget);
    expect(find.text('per month'), findsOneWidget);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Next billing'), findsOneWidget);
    expect(find.text('Nov 28, 2026'), findsOneWidget);

    // 6. Verify Card 5: Support & Contact
    expect(find.text('Support & Contact'), findsOneWidget);
    expect(find.text('Need help? Get in touch with the PG Owner support team.'), findsOneWidget);
    expect(find.text('Email Support'), findsOneWidget);
    expect(find.text('Typically replies within 2-4 hours'), findsOneWidget);
    expect(find.text('support@pgowner.com'), findsOneWidget);
    expect(find.text('Phone Support'), findsOneWidget);
    expect(find.text('Available Mon-Fri, 9 AM - 6 PM'), findsOneWidget);
    expect(find.text('1800 123 4567'), findsOneWidget);
    expect(find.text('Help Center'), findsOneWidget);
    expect(find.text('Browse FAQs and tutorials'), findsOneWidget);
    expect(find.text('Visit Help Center'), findsOneWidget);

    // 7. Verify Log Out Button
    expect(find.text('Log Out of PG Owner'), findsOneWidget);
  });

  testWidgets('Theme button switches theme mode dynamically', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await AppTheme.setThemeMode('System Default');

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: AppTheme.themeModeNotifier,
        builder: (context, mode, _) {
          return MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: const Scaffold(body: SettingsScreen()),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial theme state
    expect(AppTheme.themeModeNotifier.value, equals(ThemeMode.system));
    expect(AppTheme.themeNameNotifier.value, equals('System Default'));

    // Open Theme dropdown
    final themeDropdown = find.text('System Default');
    expect(themeDropdown, findsOneWidget);
    await tester.tap(themeDropdown);
    await tester.pumpAndSettle();

    // Select 'Dark' from dropdown menu
    final darkItem = find.text('Dark').last;
    await tester.tap(darkItem);
    await tester.pumpAndSettle();

    // Verify theme switched to Dark mode
    expect(AppTheme.themeModeNotifier.value, equals(ThemeMode.dark));
    expect(AppTheme.themeNameNotifier.value, equals('Dark'));

    // Open Theme dropdown again
    final currentDarkDropdown = find.text('Dark');
    expect(currentDarkDropdown, findsOneWidget);
    await tester.tap(currentDarkDropdown);
    await tester.pumpAndSettle();

    // Select 'Light'
    final lightItem = find.text('Light').last;
    await tester.tap(lightItem);
    await tester.pumpAndSettle();

    // Verify theme switched to Light mode
    expect(AppTheme.themeModeNotifier.value, equals(ThemeMode.light));
    expect(AppTheme.themeNameNotifier.value, equals('Light'));
  });

  testWidgets('Edit profile dialog updates fields and state', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Edit Profile
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Account Profile'), findsOneWidget);

    // Update owner name field
    final nameField = find.widgetWithText(TextField, 'Owner Manager');
    await tester.enterText(nameField, 'Jane Doe Admin');

    // Save
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    // Verify updated on the screen
    expect(find.text('Jane Doe Admin'), findsOneWidget);
  });

  testWidgets('Log out button opens themed Confirm Logout dialog matching PG Admin theme', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Log Out button
    final logoutBtn = find.text('Log Out of PG Owner');
    expect(logoutBtn, findsOneWidget);
    await tester.ensureVisible(logoutBtn);
    await tester.pumpAndSettle();
    await tester.tap(logoutBtn);
    await tester.pumpAndSettle();

    // Verify Themed Confirm Logout Dialog
    expect(find.text('Confirm Logout'), findsOneWidget);
    expect(find.text('Are you sure you want to log out of PG Owner?'), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Log Out'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Logout'), findsNothing);
  });
}
