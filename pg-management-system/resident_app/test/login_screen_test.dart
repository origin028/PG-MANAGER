import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resident_app/core/theme/app_theme.dart';
import 'package:resident_app/features/auth/login_screen.dart';

class _StubHttpClient implements HttpClient {
  final int statusCode;
  final Map<String, dynamic> body;

  _StubHttpClient({
    required this.statusCode,
    required this.body,
  });

  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubHttpClientRequest(statusCode: statusCode, body: body);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final Map<String, dynamic> body;

  _StubHttpClientRequest({
    required this.statusCode,
    required this.body,
  });

  @override
  final HttpHeaders headers = _StubHttpHeaders();

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  bool bufferOutput = true;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<HttpClientResponse> close() async =>
      _StubHttpClientResponse(statusCode: statusCode, body: body);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> _bytes;

  _StubHttpClientResponse({
    required this.statusCode,
    required Map<String, dynamic> body,
  }) : _bytes = utf8.encode(jsonEncode(body));

  @override
  int get contentLength => _bytes.length;

  @override
  final HttpHeaders headers = _StubHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('LoginScreen UI Redesign Tests', () {
    testWidgets('LoginScreen renders Light & Dark themes cleanly across viewports 320-412 without overflow',
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
            home: const LoginScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(lightScaffold.backgroundColor, const Color(0xFFF2F5F4));
        expect(find.text('PG Pilot'), findsOneWidget);
        expect(find.text('Resident portal for your PG stay'), findsOneWidget);
        expect(find.text('Mobile number'), findsOneWidget);
        expect(find.text('+91'), findsOneWidget);
        expect(find.text('Get OTP'), findsOneWidget);
        expect(find.text('Create your account'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: const LoginScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(darkScaffold.backgroundColor, const Color(0xFF0B1417));
        expect(find.text('PG Pilot'), findsOneWidget);
        expect(find.text('Get OTP'), findsOneWidget);
      }
    });

    testWidgets('LoginScreen validates mobile number input and triggers OTP dialog on API success',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: const LoginScreen(),
            ),
          );
          await tester.pumpAndSettle();

          // Submit empty / invalid mobile number
          await tester.tap(find.text('Get OTP'));
          await tester.pumpAndSettle();
          expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
          expect(find.text('Please enter a valid 10-digit mobile number'), findsOneWidget);

          // Enter valid 10-digit mobile number and tap Get OTP
          await tester.enterText(find.byType(TextFormField), '9876543210');
          await tester.pumpAndSettle();
          expect(find.text('Enter a valid 10-digit mobile number'), findsNothing);

          await tester.tap(find.text('Get OTP'));
          await tester.pumpAndSettle();

          // Redesigned OTP verification screen opens cleanly
          expect(find.text("Verify it's you"), findsOneWidget);
          expect(find.textContaining('a***@example.com'), findsOneWidget);
          expect(find.text('Verify OTP'), findsOneWidget);
        },
        createHttpClient: (_) => _StubHttpClient(
          statusCode: 200,
          body: {'email_masked': 'a***@example.com'},
        ),
      );
    });

    testWidgets('LoginScreen handles PENDING_APPROVAL API error state cleanly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: const LoginScreen(),
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextFormField), '9876543210');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Get OTP'));
          await tester.pumpAndSettle();

          expect(find.text('Approval Pending'), findsOneWidget);
        },
        createHttpClient: (_) => _StubHttpClient(
          statusCode: 403,
          body: {
            'error': {
              'code': 'PENDING_APPROVAL',
              'message': 'Pending admin approval',
            },
          },
        ),
      );
    });

    testWidgets('LoginScreen preserves Register switch and reduced-motion accessibility mode',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: LoginScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('Create account'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(find.text('PG Pilot'), findsOneWidget);
    });
  });
}
