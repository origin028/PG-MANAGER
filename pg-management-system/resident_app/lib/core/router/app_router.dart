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

CustomTransitionPage<void> _buildSlideFadePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration:
        disableAnim ? Duration.zero : const Duration(milliseconds: 240),
    reverseTransitionDuration:
        disableAnim ? Duration.zero : const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (disableAnim) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.035, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

CustomTransitionPage<void> _buildTabFadePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration:
        disableAnim ? Duration.zero : const Duration(milliseconds: 180),
    reverseTransitionDuration:
        disableAnim ? Duration.zero : const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (disableAnim) return child;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: child,
      );
    },
  );
}

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
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const LoginScreen()),
    ),
    GoRoute(
      path: '/register',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const RegisterScreen()),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const ProfileScreen()),
    ),
    GoRoute(
      path: '/property-details',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const PropertyDetailsScreen()),
    ),
    GoRoute(
      path: '/raise-complaint',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const RaiseComplaintScreen()),
    ),
    GoRoute(
      path: '/call-management',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const CallManagementScreen()),
    ),
    GoRoute(
      path: '/rent-deposit',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const RentDepositScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const SettingsScreen()),
    ),
    GoRoute(
      path: '/complaints',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const ComplaintsScreen()),
    ),
    GoRoute(
      path: '/all-complaints',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const AllComplaintsScreen()),
    ),
    GoRoute(
      path: '/notices',
      pageBuilder: (context, state) =>
          _buildSlideFadePage(context, state, const NoticesScreen()),
    ),
    GoRoute(
      path: '/rent-payment',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return _buildSlideFadePage(
          context,
          state,
          RentPaymentScreen(invoiceData: extra),
        );
      },
    ),
    GoRoute(
      path: '/payment-status',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _buildSlideFadePage(
          context,
          state,
          PaymentStatusScreen(paymentData: extra),
        );
      },
    ),
    GoRoute(
      path: '/receipt',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _buildSlideFadePage(
          context,
          state,
          ReceiptScreen(receiptData: extra),
        );
      },
    ),
    GoRoute(
      path: '/poc-upi-india',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return _buildSlideFadePage(
          context,
          state,
          PocFlutterUpiScreen(invoiceData: extra),
        );
      },
    ),
    GoRoute(
      path: '/poc-upi-pay',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return _buildSlideFadePage(
          context,
          state,
          PocUpiPayScreen(invoiceData: extra),
        );
      },
    ),

    // Main ShellRoute (Bottom Navigation is VISIBLE for the 4 primary tabs)
    ShellRoute(
      builder: (context, state, child) => MainLayout(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              _buildTabFadePage(context, state, const HomeScreen()),
        ),
        GoRoute(
          path: '/payments',
          pageBuilder: (context, state) =>
              _buildTabFadePage(context, state, const PaymentsScreen()),
        ),
        GoRoute(
          path: '/food-menu',
          pageBuilder: (context, state) =>
              _buildTabFadePage(context, state, const FoodMenuScreen()),
        ),
        GoRoute(
          path: '/menu',
          pageBuilder: (context, state) =>
              _buildTabFadePage(context, state, const MenuScreen()),
        ),
      ],
    ),
  ],
);
