import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:admin_app/core/router/app_router.dart';
import 'package:admin_app/features/auth/login_screen.dart';
import 'package:admin_app/core/services/admin_auth_service.dart';

void main() {
  testWidgets('RegisterScreen displays all single-step fields in order and validates', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AdminAuthService.registerHandler = ({
      required String businessName,
      required String email,
      required String password,
      required String confirmPassword,
      required String superKey,
      String? fullName,
      String? phone,
    }) async {
      return {'message': 'Registration Successful!'};
    };
    addTearDown(() {
      AdminAuthService.registerHandler = null;
    });


    final testRouter = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
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
    expect(find.text('PG Owner Registration'), findsOneWidget);
    expect(find.text('Create your account to manage properties and rooms'), findsOneWidget);

    // Verify all input fields in order
    expect(find.widgetWithText(TextField, 'Business Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email Address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Super Key'), findsOneWidget);

    // Verify Checkbox
    expect(find.text('I agree to the Terms & Conditions'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);

    // Verify Register Button
    expect(find.widgetWithText(ElevatedButton, 'Register'), findsOneWidget);

    // Verify Log In Link
    expect(find.text('Already have an account?'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);

    // 1. Attempt to register with empty fields -> should show error SnackBar
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();
    expect(find.text('Please fill all fields including Super Key'), findsOneWidget);

    // 2. Fill in the fields
    await tester.enterText(find.widgetWithText(TextField, 'Business Name'), 'Cozy Nest PG');
    await tester.enterText(find.widgetWithText(TextField, 'Email Address'), 'owner@cozynest.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Secret123!');
    await tester.enterText(find.widgetWithText(TextField, 'Super Key'), 'SK-889900');
    await tester.pump();

    // Tap register without agreeing to terms -> should prompt terms error
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();
    expect(find.text('Please agree to the Terms & Conditions'), findsOneWidget);

    // 3. Check the Terms & Conditions checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    // 4. Tap register with all fields and terms checked
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();

    // Verify green success SnackBar
    expect(find.text('Registration Successful!'), findsOneWidget);

    // Settle navigation to /login
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('RegisterScreen Log In button routes to LoginScreen', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AdminAuthService.registerHandler = ({
      required String businessName,
      required String email,
      required String password,
      required String confirmPassword,
      required String superKey,
      String? fullName,
      String? phone,
    }) async {
      return {'message': 'Registration Successful!'};
    };
    addTearDown(() {
      AdminAuthService.registerHandler = null;
    });


    final testRouter = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: testRouter,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PG Owner Registration'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
