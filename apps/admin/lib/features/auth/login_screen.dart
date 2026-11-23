import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/admin_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.successGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty) {
      _showError('Please enter your administrator email address.');
      return;
    }
    if (password.isEmpty) {
      _showError('Please enter your password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await AdminAuthService.login(email: email, password: password);
      if (!mounted) return;
      _showSuccess(res['message']?.toString() ?? 'Authenticated successfully. Welcome back!');
      context.go('/dashboard');
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      if (mounted) {
        if (TokenStorage.isAuthenticated) {
          context.go('/dashboard');
        } else {
          _showError('Unable to connect to the server. Please check your network.');
        }
      }
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

    final formWidget = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Brand Badge
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

              // Title & Subtitle
              Text(
                'Welcome Back',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with your administrator credentials',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),

              // Email Address
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isLoading,
                style: GoogleFonts.manrope(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'admin@pgpilot.com',
                  prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primaryTeal, size: 20),
                  filled: true,
                  fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enabled: !_isLoading,
                style: GoogleFonts.manrope(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryTeal, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Log In Button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Log In',
                        style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
              ),
              const SizedBox(height: 22),

              // Register Link
              Center(
                child: TextButton(
                  onPressed: () => context.go('/register'),
                  child: Text(
                    'New here? Register your PG',
                    style: GoogleFonts.manrope(
                      color: AppTheme.primaryTeal,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
        body: SafeArea(child: formWidget),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Left Decorative Hero Pane (Matching .ab in PG_Pilot_Admin_Pro.html)
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
                  // Brand Header
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
                      Text(
                        'PG Owner',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),

                  // Middle Value Proposition
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Run every PG with clarity.',
                        style: GoogleFonts.manrope(
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
                        child: Text(
                          'Residents, rooms, rent and daily operations, managed from one calm workspace.',
                          style: GoogleFonts.manrope(
                            color: const Color(0xFFB9CCD3),
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Footer Copyright
                  Text(
                    '© 2026 PG Pilot',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF7FA0AB),
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
              child: formWidget,
            ),
          ),
        ],
      ),
    );
  }
}
