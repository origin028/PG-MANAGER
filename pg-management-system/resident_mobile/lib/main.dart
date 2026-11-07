import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/pushy_service.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/invoice_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/receipt_provider.dart';
import 'providers/resident_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/invoice_detail_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/receipts_screen.dart';
import 'widgets/loading_indicator.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load custom configured backend URL if saved
  await AppConfig.init();

  // Initialize push notification listener
  await PushyService().init();

  runApp(const OriginPGResidentApp());
}

class OriginPGResidentApp extends StatelessWidget {
  const OriginPGResidentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ResidentProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        ChangeNotifierProvider(create: (_) => ReceiptProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        title: 'Origin PG Resident',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: '/',
        routes: {
          '/': (_) => const AuthCheckWrapper(),
          '/login': (_) => const LoginScreen(),
          '/dashboard': (_) => const DashboardScreen(),
          '/invoices': (_) => const InvoicesScreen(),
          '/receipts': (_) => const ReceiptsScreen(),
          '/notifications': (_) => const NotificationsScreen(),
        },
      ),
    );
  }
}

class AuthCheckWrapper extends StatefulWidget {
  const AuthCheckWrapper({super.key});

  @override
  State<AuthCheckWrapper> createState() => _AuthCheckWrapperState();
}

class _AuthCheckWrapperState extends State<AuthCheckWrapper> {
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).checkAuthStatus();
      _listenForNotificationTaps();
    });
  }

  void _listenForNotificationTaps() {
    _notificationSubscription = PushyService().onNotificationTapped.listen((data) {
      debugPrint('[Pushy] Notification tapped with payload: $data');
      final invoiceId = data['invoice_id'] ?? data['id'];
      if (invoiceId != null && invoiceId.toString().isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId.toString()),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_work_rounded, size: 64, color: AppTheme.primary),
              SizedBox(height: 24),
              AppLoadingIndicator(message: 'Starting Origin PG Resident...'),
            ],
          ),
        ),
      );
    }

    if (authProvider.isAuthenticated) {
      return const DashboardScreen();
    }

    return const LoginScreen();
  }
}
