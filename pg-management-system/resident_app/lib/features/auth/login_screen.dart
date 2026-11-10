import '../../core/network/token_storage.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/resident_auth_service.dart';
import '../../core/services/resident_api_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool initialIsRegister;
  const LoginScreen({super.key, this.initialIsRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isRegisterMode;
  final _phoneLoginController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isRegisterMode = widget.initialIsRegister;
    AppData.loadResidentsFromStorage().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _phoneLoginController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final phone = _phoneLoginController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await ResidentAuthService.requestLoginOtp(phone);
      if (!mounted) return;
      final emailMasked = res['email_masked']?.toString() ?? 'your registered email';
      _showLoginOtpDialog(phone, emailMasked);
    } on ApiException catch (e) {
      if (mounted) {
        if (e.code == 'PENDING_APPROVAL') {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706)),
                  SizedBox(width: 10),
                  Text('Approval Pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'Your registration is awaiting admin approval. Please wait for approval before logging in.',
                style: TextStyle(fontSize: 14, height: 1.4, color: AppTheme.textDark),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else if (e.code == 'ACCOUNT_REJECTED') {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.cancel_outlined, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Application Rejected', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                e.message,
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppTheme.textDark),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to request OTP. Please verify your phone number.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showNewRegistrationModal(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (dialogCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(dialogCtx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle pill
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0x1A4F46E5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Resident Registration',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              Text(
                                'Request admission to PG management',
                                style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textGrey),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name Field
                    const Text('Full Name *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g. Rohan Mehta',
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryBlue),
                        filled: true,
                        fillColor: AppTheme.softGrey,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone Field
                    const Text('Phone Number *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'e.g. 9876543290',
                        prefixIcon: const Icon(Icons.phone_iphone_rounded, color: AppTheme.primaryBlue),
                        filled: true,
                        fillColor: AppTheme.softGrey,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),

                    if (localError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        localError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit Button
                    ElevatedButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        final phone = phoneController.text.trim();

                        if (name.isEmpty) {
                          setSheetState(() => localError = 'Please enter your full name.');
                          return;
                        }
                        if (phone.length < 10) {
                          setSheetState(() => localError = 'Please enter a valid 10-digit mobile number.');
                          return;
                        }

                        Navigator.pop(sheetCtx);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Registration request sent to Admin. Please wait for approval.'),
                            backgroundColor: AppTheme.successGreen,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Submit Registration',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLoginOtpDialog(String phone, [String emailMasked = '']) {
    final otpController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top circular blue icon
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppTheme.blueGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x4D4F46E5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Enter OTP',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              emailMasked.isNotEmpty
                  ? 'A 6-digit verification code has been sent to your registered email ($emailMasked)'
                  : 'A 6-digit verification code has been sent to +91 $phone',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
            ),
            const SizedBox(height: 20),

            // OTP Input with soft light-grey background and rounded corners
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.softGrey,
                hintText: '• • • • • •',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFEDF2F7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                ),
              ),
              maxLength: 6,
            ),
            const SizedBox(height: 12),

            const SizedBox(height: 24),

            // Solid Blue 'Verify OTP' button with rounded corners (borderRadius: 16)
            ElevatedButton(
              onPressed: () async {
                final otp = otpController.text.trim();
                if (otp.length != 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid 6-digit OTP code'), backgroundColor: Colors.red),
                  );
                  return;
                }

                try {
                  await ResidentAuthService.verifyLoginOtp(phone: phone, otp: otp);
                  final profile = await ResidentApiService.getProfile();
                  AppData.currentResident = profile;
                  await TokenStorage.saveResidentProfile(profile);

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }

                  if (mounted) {
                    final residentName = profile['full_name'] ?? profile['name'] ?? 'Resident';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Welcome back, $residentName!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    context.go('/home', extra: AppData.currentResident);
                  }
                } on ApiException catch (e) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
                    );
                  }
                } catch (_) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      const SnackBar(content: Text('Verification failed. Please check OTP.'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Verify OTP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRegisterMode) {
      return RegisterScreen(
        onSwitchToLogin: () => setState(() => _isRegisterMode = false),
      );
    }

    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final borderCol = AppTheme.borderCol(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final pageBg = AppTheme.pageBg(context);
    final inputBg = isDark ? const Color(0xFF0F172A) : AppTheme.softGrey;

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  // Large circular blue icon with soft gradient at the top
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: AppTheme.blueGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x594F46E5),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.apartment_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Brand Title & Subtitle
                  Text(
                    'PG Pilot',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textPri,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Resident Mobile Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: textSec,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Auth Mode Switcher Tab
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderCol),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Login',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isRegisterMode = true),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Register',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.textGrey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Login Form Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x1A000000) : const Color(0x08000000),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mobile Number',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPri,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Input field with soft light-grey background & rounded corners (no harsh borders)
                        TextFormField(
                          controller: _phoneLoginController,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPri),
                          decoration: InputDecoration(
                            prefixIcon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.phone_iphone_rounded, color: AppTheme.primaryBlue, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    '+91',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textPri,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 18,
                                    child: VerticalDivider(color: borderCol, width: 1),
                                  ),
                                ],
                              ),
                            ),
                            hintText: 'Enter 10-digit number',
                            hintStyle: TextStyle(color: textSec, fontSize: 14),
                            filled: true,
                            fillColor: inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: borderCol),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Solid Blue 'Get OTP' button with rounded corners (borderRadius: 16)
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Get OTP',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Demo Accounts Selector Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt_rounded, size: 18, color: AppTheme.primaryBlue),
                            const SizedBox(width: 6),
                            Text(
                              'Quick Demo Profiles (One-Tap)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textPri,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...AppData.residents.take(3).map((resident) {
                          final isPending = resident['room_number'] == null || resident['status'] == 'Pending';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: InkWell(
                              onTap: () async {
                                if (isPending) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      title: const Row(
                                        children: [
                                          Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706)),
                                          SizedBox(width: 10),
                                          Text('Approval Pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      content: Text(
                                        'Registration for ${resident['name']} is currently awaiting admin approval. Please wait for approval or select an active profile.',
                                        style: const TextStyle(fontSize: 14, height: 1.4, color: AppTheme.textDark),
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryBlue,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }

                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = GoRouter.of(context);

                                AppData.currentResident = Map<String, dynamic>.from(resident);
                                await TokenStorage.saveTokens(
                                  accessToken: 'demo_token_${resident['phone'] ?? '123'}',
                                  refreshToken: 'demo_refresh_${resident['phone'] ?? '123'}',
                                  user: {
                                    'full_name': resident['name'],
                                    'phone': resident['phone'],
                                    'email': resident['email'],
                                  },
                                );
                                await TokenStorage.saveResidentProfile(Map<String, dynamic>.from(resident));

                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Logged in as ${resident['name']}!'),
                                    backgroundColor: AppTheme.primaryBlue,
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                                navigator.go('/home', extra: resident);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: inputBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isPending
                                          ? const Color(0xFFFEF3C7)
                                          : const Color(0xFFECFDF5),
                                      child: Text(
                                        resident['name'] != null && resident['name'].toString().isNotEmpty
                                            ? resident['name'][0].toUpperCase()
                                            : 'R',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isPending ? const Color(0xFFB45309) : const Color(0xFF059669),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            resident['name'] ?? '',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPri),
                                          ),
                                          Text(
                                            isPending ? 'Pending Approval' : 'Active • Room ${resident['room_number'] ?? 101}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isPending ? const Color(0xFFB45309) : AppTheme.textGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.textGrey),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Switch to Registration prompt
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _isRegisterMode = true),
                      child: RichText(
                        text: const TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
                          children: [
                            TextSpan(
                              text: 'Self Register',
                              style: TextStyle(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Small 'New Registration' text button at bottom
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _showNewRegistrationModal(context),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 15, color: AppTheme.primaryBlue),
                      label: const Text(
                        'New Registration',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
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
