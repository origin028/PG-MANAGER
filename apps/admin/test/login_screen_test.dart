import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:admin_app/features/auth/login_screen.dart';
import 'package:admin_app/core/router/app_router.dart';

void main() {
  testWidgets('LoginScreen displays pure Email + Password fields without 2FA or Super Key prompt', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final testRouter = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(body: Text('Admin Dashboard')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: testRouter,
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and Subtitle
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in with your administrator credentials'), findsOneWidget);

    // Verify Email and Password fields are present
    expect(find.widgetWithText(TextFormField, 'Email Address'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));

    // Verify Super Key / 2FA fields are NOT present
    expect(find.text('Super Key (2FA Verification)'), findsNothing);
    expect(find.text('Resend Super Key'), findsNothing);

    // Verify Log In button and Register link
    expect(find.widgetWithText(ElevatedButton, 'Log In'), findsOneWidget);
    expect(find.text('New here? Register your PG'), findsOneWidget);

    // 1. Submit empty email -> validation error
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
    await tester.pump();
    expect(find.text('Please enter your administrator email address.'), findsOneWidget);

    // 2. Fill email only -> prompt for password
    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'admin@originpg.com');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
    await tester.pump();
    expect(find.text('Please enter your password.'), findsOneWidget);

    // 3. New here? Register your PG navigates to /register
    await tester.tap(find.text('New here? Register your PG'));
    await tester.pumpAndSettle();
    expect(find.text('PG Owner Registration'), findsOneWidget);
  });
}
