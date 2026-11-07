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
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _superKeyController = TextEditingController();

  bool _agreedToTerms = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _businessNameController.dispose();
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
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppTheme.primaryBlue, width: 1.5),
      ),
    );
  }

  Future<void> _onRegister() async {
    final messenger = ScaffoldMessenger.of(context);
    final businessName = _businessNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final superKey = _superKeyController.text.trim().toUpperCase();

    messenger.hideCurrentSnackBar();

    if (businessName.isEmpty || email.isEmpty || password.isEmpty || superKey.isEmpty) {
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
        businessName: businessName,
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.home_work_rounded, size: 70, color: AppTheme.primaryBlue),
                  const SizedBox(height: 16),
                  const Text(
                    'PG Owner Registration',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your account to manage properties and rooms',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppTheme.textGrey),
                  ),
                  const SizedBox(height: 28),

                  // 1. Business Name (TextField)
                  TextField(
                    controller: _businessNameController,
                    decoration: _buildInputDecoration(
                      hintText: 'Business Name',
                      prefixIcon: const Icon(Icons.business_outlined, color: AppTheme.primaryBlue, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Email Address (TextField)
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _buildInputDecoration(
                      hintText: 'Email Address',
                      prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primaryBlue, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Password (TextField, obscured)
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: _buildInputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryBlue, size: 20),
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

                  // 4. Super Key (TextField, NEW) - Add this below the password.
                  TextField(
                    controller: _superKeyController,
                    decoration: _buildInputDecoration(
                      hintText: 'Super Key',
                      prefixIcon: const Icon(Icons.vpn_key_outlined, color: AppTheme.primaryBlue, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. Checkbox: 'I agree to the Terms & Conditions'
                  Row(
                    children: [
                      Checkbox(
                        value: _agreedToTerms,
                        activeColor: AppTheme.primaryBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                          child: const Text(
                            'I agree to the Terms & Conditions',
                            style: TextStyle(
                              color: AppTheme.textDark,
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
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 20),

                  // 7. Bottom Text: 'Already have an account? Log In' (make 'Log In' clickable to go to /login)
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      const Text(
                        'Already have an account?',
                        style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
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
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. ROUTER CONFIGURATION
// ==========================================
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
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
