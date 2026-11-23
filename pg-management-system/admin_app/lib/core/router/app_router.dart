import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/admin_layout.dart';
import '../network/token_storage.dart';
import '../network/api_exception.dart';
import '../services/admin_auth_service.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/properties/properties_screen.dart';
import '../../features/rooms_beds/rooms_beds_screen.dart';
import '../../features/residents/residents_screen.dart';
import '../../features/payments/payments_screen.dart';
import '../../features/complaints/complaints_screen.dart';
import '../../features/expenses/expenses_screen.dart';
import '../../features/announcements/announcements_screen.dart';
import '../../features/staff/staff_screen.dart';
import '../../features/leads/leads_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/food_menu/food_menu_screen.dart';

// ==========================================
// 1. SPLASH SCREEN
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        if (TokenStorage.isAuthenticated) {
          context.go('/dashboard');
        } else {
          context.go('/login');
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_work_rounded, size: 100, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              'PG PILOT',
              style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2.0),
            ),
            const SizedBox(height: 10),
            Text(
              'Pilot Your PG. Stay in Control.',
              style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. REGISTER SCREEN
// ==========================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _superKeyController = TextEditingController();

  bool _agreedToTerms = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _superKeyController.dispose();
    super.dispose();
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF6F9F8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppTheme.borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppTheme.borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(11)),
        borderSide: BorderSide(color: AppTheme.primaryTeal, width: 1.5),
      ),
    );
  }

  Future<void> _onRegister() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final superKey = _superKeyController.text.trim().toUpperCase();

    messenger.hideCurrentSnackBar();

    if (email.isEmpty || password.isEmpty || superKey.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields including Super Key'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password.length < 8) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 8 characters long'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'\d').hasMatch(password)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password must contain at least one letter and one number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_agreedToTerms) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Terms & Conditions'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await AdminAuthService.register(
        email: email,
        password: password,
        confirmPassword: password,
        superKey: superKey,
      );

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Registration Successful!'),
          backgroundColor: AppTheme.successGreen,
        ),
      );

      context.go('/login');
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to connect to the server. Please check your network.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final formContent = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.lightTealDark : AppTheme.lightTeal,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Center(
                    child: Icon(Icons.apartment_rounded, color: AppTheme.primaryTeal, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'PG Owner Registration',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                  color: isDark ? AppTheme.primaryTextDark : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your account to manage properties and rooms',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: isDark ? AppTheme.secondaryTextDark : AppTheme.textGrey),
              ),
              const SizedBox(height: 28),

              // 1. Email Address (TextField)
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _buildInputDecoration(
                  hintText: 'Email Address',
                  prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primaryTeal, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Password (TextField, obscured)
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _buildInputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryTeal, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppTheme.textGrey,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. Super Key (TextField)
              TextField(
                controller: _superKeyController,
                decoration: _buildInputDecoration(
                  hintText: 'Super Key',
                  prefixIcon: const Icon(Icons.vpn_key_outlined, color: AppTheme.primaryTeal, size: 20),
                ),
              ),
              const SizedBox(height: 20),

              // 5. Checkbox: 'I agree to the Terms & Conditions'
              Row(
                children: [
                  Checkbox(
                    value: _agreedToTerms,
                    activeColor: AppTheme.primaryTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                      child: Text(
                        'I agree to the Terms & Conditions',
                        style: TextStyle(
                          color: isDark ? AppTheme.primaryTextDark : AppTheme.textDark,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 6. Register Button
              ElevatedButton(
                onPressed: _isLoading ? null : _onRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Register',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 20),

              // 7. Bottom Text: 'Already have an account? Log In'
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    'Already have an account?',
                    style: TextStyle(color: isDark ? AppTheme.secondaryTextDark : AppTheme.textGrey, fontSize: 14),
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        color: AppTheme.primaryTeal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
        body: SafeArea(child: formContent),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Left Decorative Hero Pane
          Expanded(
            flex: 11,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 48),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryNavy,
                    Color(0xFF0F3446),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.brightTeal, AppTheme.primaryTeal],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Icon(Icons.apartment_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'PG Owner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Run every PG with clarity.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.3,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: const Text(
                          'Residents, rooms, rent and daily operations, managed from one calm workspace.',
                          style: TextStyle(
                            color: Color(0xFFB9CCD3),
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    '© 2026 PG Pilot',
                    style: TextStyle(
                      color: Color(0xFF7FA0AB),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Form Pane
          Expanded(
            flex: 10,
            child: Container(
              color: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
              child: formContent,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. ROUTER CONFIGURATION
// ==========================================
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  errorBuilder: (context, state) => TokenStorage.isAuthenticated
      ? const AdminLayout(child: DashboardScreen())
      : const LoginScreen(),
  routes: [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          TokenStorage.isAuthenticated ? '/dashboard' : '/login',
    ),
    GoRoute(
      path: '/admin',
      redirect: (context, state) =>
          TokenStorage.isAuthenticated ? '/dashboard' : '/login',
    ),
    GoRoute(
      path: '/admin/:subpath',
      redirect: (context, state) {
        final sub = state.pathParameters['subpath'];
        return sub != null ? '/$sub' : '/dashboard';
      },
    ),
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
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
      builder: (context, state) => const AdminLayout(child: DashboardScreen()),
    ),
    GoRoute(
      path: '/properties',
      builder: (context, state) => const AdminLayout(child: PropertiesScreen()),
    ),
    GoRoute(
      path: '/rooms',
      builder: (context, state) {
        final roomQuery = state.uri.queryParameters['room'] ?? state.uri.queryParameters['search'];
        return AdminLayout(child: RoomsBedsScreen(initialRoom: roomQuery));
      },
    ),
    GoRoute(
      path: '/residents',
      builder: (context, state) => const AdminLayout(child: ResidentsScreen()),
    ),
    GoRoute(
      path: '/payments',
      builder: (context, state) => const AdminLayout(child: PaymentsScreen()),
    ),
    GoRoute(
      path: '/complaints',
      builder: (context, state) => const AdminLayout(child: ComplaintsScreen()),
    ),
    GoRoute(
      path: '/expenses',
      builder: (context, state) => const AdminLayout(child: ExpensesScreen()),
    ),
    GoRoute(
      path: '/announcements',
      builder: (context, state) => const AdminLayout(child: AnnouncementsScreen()),
    ),
    GoRoute(
      path: '/staff',
      builder: (context, state) => const AdminLayout(child: StaffScreen()),
    ),
    GoRoute(
      path: '/leads',
      builder: (context, state) => const AdminLayout(child: LeadsScreen()),
    ),
    GoRoute(
      path: '/reports',
      builder: (context, state) => const AdminLayout(child: ReportsScreen()),
    ),
    GoRoute(
      path: '/food-menu',
      builder: (context, state) => const AdminLayout(child: FoodMenuScreen()),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const AdminLayout(child: SettingsScreen()),
    ),
  ],
);
