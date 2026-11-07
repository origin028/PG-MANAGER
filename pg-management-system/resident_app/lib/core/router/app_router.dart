import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/main_layout.dart';
import '../../features/home/home_screen.dart';
import '../../features/payments/payments_screen.dart';
import '../../features/payments/rent_payment_screen.dart';
import '../../features/payments/payment_status_screen.dart';
import '../../features/payments/receipt_screen.dart';
import '../../features/payments/poc_flutter_upi_screen.dart';
import '../../features/payments/poc_upi_pay_screen.dart';
import '../../features/complaints/complaints_screen.dart';
import '../../features/complaints/raise_complaint_screen.dart';
import '../../features/complaints/all_complaints_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/menu_screen.dart';
import '../../features/profile/property_details_screen.dart';
import '../../features/profile/call_management_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/profile/rent_deposit_screen.dart';
import '../../features/notices/notices_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/food_menu/food_menu_screen.dart';
import '../network/token_storage.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final uriStr = state.uri.toString();
    final isAuthRoute = uriStr == '/login' || uriStr == '/register';

    if (TokenStorage.isAuthenticated) {
      if (isAuthRoute || uriStr == '/') {
        return '/home';
      }
    } else {
      if (!isAuthRoute) {
        return '/login';
      }
    }
    return null;
  },
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Route not found: ${state.uri}'),
    ),
  ),
  routes: [
    // Top-Level Screens (Bottom Navigation is HIDDEN)
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
    GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
    GoRoute(path: '/property-details', builder: (context, state) => const PropertyDetailsScreen()),
    GoRoute(path: '/raise-complaint', builder: (context, state) => const RaiseComplaintScreen()),
    GoRoute(path: '/call-management', builder: (context, state) => const CallManagementScreen()),
    GoRoute(path: '/rent-deposit', builder: (context, state) => const RentDepositScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/complaints', builder: (context, state) => const ComplaintsScreen()),
    GoRoute(path: '/all-complaints', builder: (context, state) => const AllComplaintsScreen()),
    GoRoute(path: '/notices', builder: (context, state) => const NoticesScreen()),
    GoRoute(
      path: '/rent-payment',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RentPaymentScreen(invoiceData: extra);
      },
    ),
    GoRoute(
      path: '/payment-status',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return PaymentStatusScreen(paymentData: extra);
      },
    ),
    GoRoute(
      path: '/receipt',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ReceiptScreen(receiptData: extra);
      },
    ),
    GoRoute(
      path: '/poc-upi-india',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PocFlutterUpiScreen(invoiceData: extra);
      },
    ),
    GoRoute(
      path: '/poc-upi-pay',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PocUpiPayScreen(invoiceData: extra);
      },
    ),
    
    // Main ShellRoute (Bottom Navigation is VISIBLE for the 4 primary tabs)
    ShellRoute(
      builder: (context, state, child) => MainLayout(child: child),
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/payments', builder: (context, state) => const PaymentsScreen()),
        GoRoute(path: '/food-menu', builder: (context, state) => const FoodMenuScreen()),
        GoRoute(path: '/menu', builder: (context, state) => const MenuScreen()),
      ],
    ),
  ],
);
