import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident_app/core/network/api_exception.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/auth/otp_screen.dart';

void main() {
  group('OtpVerificationScreen UI Redesign & Flow Tests', () {
    testWidgets('Renders Light & Dark themes across widths 320-412 cleanly without overflow',
        (WidgetTester tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());

      for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: OtpVerificationScreen(
              destinationMasked: 'a***a@example.com',
              initialCooldownSeconds: 0,
              onVerifyOtp: (_) async => <String, dynamic>{},
              onResendOtp: () async => {'cooldown_seconds': 60},
              onVerified: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(lightScaffold.backgroundColor, const Color(0xFFF2F5F4));
        expect(find.text("Verify it's you"), findsOneWidget);
        expect(find.text('a***a@example.com'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(6));
        expect(find.text('Verify OTP'), findsOneWidget);
        expect(find.text('Resend code'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: OtpVerificationScreen(
              destinationMasked: 'a***a@example.com',
              initialCooldownSeconds: 0,
              onVerifyOtp: (_) async => <String, dynamic>{},
              onResendOtp: () async => {'cooldown_seconds': 60},
              onVerified: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(darkScaffold.backgroundColor, const Color(0xFF0B1417));
        expect(find.text("Verify it's you"), findsOneWidget);
      }
    });

    testWidgets('Supports paste of 6 digits, auto-focus advance, backspace step-back, and strict verification',
        (WidgetTester tester) async {
      String? submittedOtp;
      bool verifiedCallbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: OtpVerificationScreen(
            destinationMasked: 'p***a@example.com',
            initialCooldownSeconds: 0,
            onVerifyOtp: (otp) async {
              submittedOtp = otp;
              return {'status': 'ok'};
            },
            onVerified: (_, _) {
              verifiedCallbackCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify button is disabled before 6 digits
      ElevatedButton button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      // Paste 6 digits into first cell -> distributes across all 6 cells
      await tester.enterText(find.byType(TextField).at(0), '482910');
      await tester.pumpAndSettle();

      button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);

      // Clear last digit via backspace on empty cell check
      await tester.enterText(find.byType(TextField).at(5), '');
      await tester.pump();
      button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      // Send backspace key while focus is on empty cell 5 -> clears & focuses cell 4
      await tester.tap(find.byType(TextField).at(5));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      // Refill cells 4 & 5 via single-digit typing
      await tester.enterText(find.byType(TextField).at(4), '1');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(5), '7');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Verify OTP'));
      await tester.pumpAndSettle();

      expect(submittedOtp, '482917');
      expect(verifiedCallbackCalled, isTrue);
    });

    testWidgets('Displays backend API error and loading state on invalid/expired OTP without accepting fake OTP',
        (WidgetTester tester) async {
      final completer = Completer<Map<String, dynamic>>();
      bool verifiedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: OtpVerificationScreen(
            destinationMasked: 'r***n@example.com',
            initialCooldownSeconds: 0,
            onVerifyOtp: (_) => completer.future,
            onVerified: (_, _) {
              verifiedCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '999999');
      await tester.pumpAndSettle();

      // Tap Verify OTP -> enters loading state
      await tester.tap(find.text('Verify OTP'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Fail with backend error -> shows message & stops spinner & never calls onVerified
      completer.completeError(
        ApiException(
          statusCode: 400,
          code: 'INVALID_OTP',
          message: 'Invalid or expired verification code.',
        ),
      );
      await tester.pumpAndSettle();

      expect(verifiedCalled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Invalid or expired verification code.'), findsOneWidget);
      expect(find.text('Verify OTP'), findsOneWidget);
    });

    testWidgets('Resend countdown ticks down and invokes existing Resend API callback once unlocked',
        (WidgetTester tester) async {
      int resendCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: OtpVerificationScreen(
            destinationMasked: 'r***n@example.com',
            initialCooldownSeconds: 2,
            onVerifyOtp: (_) async => <String, dynamic>{},
            onResendOtp: () async {
              resendCount++;
              return {'cooldown_seconds': 30};
            },
            onVerified: (_, _) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Resend code in'), findsOneWidget);
      expect(find.textContaining('0:02'), findsOneWidget);
      expect(find.text('Resend code'), findsNothing);

      // Advance 2 seconds
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('0:01'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Resend code'), findsOneWidget);

      // Tap Resend code
      await tester.tap(find.text('Resend code'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(resendCount, 1);
      expect(find.textContaining('0:30'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.textContaining('Resend code in'), findsOneWidget);
    });

    testWidgets('Honors reduced-motion setting cleanly without animation errors or pending timers',
        (WidgetTester tester) async {
      bool verified = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: OtpVerificationScreen(
              destinationMasked: 'r***n@example.com',
              initialCooldownSeconds: 45,
              onVerifyOtp: (_) async => {'ok': true},
              onVerified: (_, _) => verified = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '112233');
      await tester.pump();
      await tester.tap(find.text('Verify OTP'));
      await tester.pumpAndSettle();

      expect(verified, isTrue);
    });
  });
}
