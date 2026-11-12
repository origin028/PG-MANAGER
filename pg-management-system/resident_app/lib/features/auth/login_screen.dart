import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/services/resident_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion_wrappers.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

class _LoginPalette {
  final bool isDark;
  final Color bg;
  final Color card;
  final Color ink;
  final Color mute;
  final Color line;
  final Color field;
  final Color teal;
  final Color softTeal;
  final Color error;
  final Color softError;
  final Color warning;
  final Color softWarning;
  final Color success;
  final Color softSuccess;

  const _LoginPalette({
    required this.isDark,
    required this.bg,
    required this.card,
    required this.ink,
    required this.mute,
    required this.line,
    required this.field,
    required this.teal,
    required this.softTeal,
    required this.error,
    required this.softError,
    required this.warning,
    required this.softWarning,
    required this.success,
    required this.softSuccess,
  });

  factory _LoginPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _LoginPalette(
        isDark: true,
        bg: Color(0xFF0B1417),
        card: Color(0xFF121E24),
        ink: Color(0xFFE8F0EF),
        mute: Color(0xFF93A5A8),
        line: Color(0xFF1F2F35),
        field: Color(0xFF172830),
        teal: Color(0xFF14998B),
        softTeal: Color(0xFF12312F),
        error: Color(0xFFFF9A8F),
        softError: Color(0xFF3A1714),
        warning: Color(0xFFF5B54A),
        softWarning: Color(0xFF3A2A0C),
        success: Color(0xFF5BD3A0),
        softSuccess: Color(0xFF0F2F24),
      );
    }
    return const _LoginPalette(
      isDark: false,
      bg: Color(0xFFF2F5F4),
      card: Color(0xFFFFFFFF),
      ink: Color(0xFF0E1A1F),
      mute: Color(0xFF56626B),
      line: Color(0xFFE6ECEA),
      field: Color(0xFFF2F6F5),
      teal: Color(0xFF0B6B63),
      softTeal: Color(0xFFE2F0EE),
      error: Color(0xFFB42318),
      softError: Color(0xFFFDECEA),
      warning: Color(0xFF92400E),
      softWarning: Color(0xFFFEF3C7),
      success: Color(0xFF0F6B4A),
      softSuccess: Color(0xFFDDF3E8),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final bool initialIsRegister;
  const LoginScreen({super.key, this.initialIsRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late bool _isRegisterMode;
  final _phoneLoginController = TextEditingController();
  late final AnimationController _logoController;
  late final AnimationController _shakeController;
  bool _logoAnimStarted = false;
  bool _isLoading = false;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _isRegisterMode = widget.initialIsRegister;
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    AppData.loadResidentsFromStorage().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_logoAnimStarted) {
      _logoAnimStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _logoController.value = 1.0;
      } else {
        _logoController.forward();
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _shakeController.dispose();
    _phoneLoginController.dispose();
    super.dispose();
  }

  void _triggerValidationShake() {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!disableAnim) {
      _shakeController.forward(from: 0);
    }
  }

  Future<void> _handleLogin() async {
    final phone = _phoneLoginController.text.trim();
    if (phone.length < 10) {
      _triggerValidationShake();
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _phoneError = null;
      _isLoading = true;
    });
    try {
      final res = await ResidentAuthService.requestLoginOtp(phone);
      if (!mounted) return;
      final emailMasked =
          res['email_masked']?.toString() ?? 'your registered email';
      final cooldownSeconds = (res['cooldown_seconds'] as num?)?.toInt() ?? 60;
      _showLoginOtpDialog(phone, emailMasked, cooldownSeconds);
    } on ApiException catch (e) {
      if (mounted) {
        final palette = _LoginPalette.of(context);
        if (e.code == 'PENDING_APPROVAL') {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: palette.line),
              ),
              backgroundColor: palette.card,
              title: Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: palette.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Approval Pending',
                      style: HomeThemeTokens.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Your registration is awaiting admin approval. Please wait for approval before logging in.',
                style: HomeThemeTokens.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: palette.mute,
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: palette.line),
              ),
              backgroundColor: palette.card,
              title: Row(
                children: [
                  Icon(Icons.cancel_outlined, color: palette.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Application Rejected',
                      style: HomeThemeTokens.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                e.message,
                style: HomeThemeTokens.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: palette.mute,
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to request OTP. Please verify your phone number.',
            ),
            backgroundColor: Colors.red,
          ),
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
    final palette = _LoginPalette.of(context);
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
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: palette.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: palette.softTeal,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.person_add_alt_1_rounded,
                            color: palette.teal,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Resident Registration',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: palette.ink,
                                ),
                              ),
                              Text(
                                'Request admission to PG management',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 12,
                                  color: palette.mute,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: palette.mute),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name Field
                    Text(
                      'Full Name *',
                      style: HomeThemeTokens.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      style: HomeThemeTokens.manrope(
                        color: palette.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Rohan Mehta',
                        hintStyle: TextStyle(color: palette.mute),
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          color: palette.teal,
                        ),
                        filled: true,
                        fillColor: palette.field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone Field
                    Text(
                      'Phone Number *',
                      style: HomeThemeTokens.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: HomeThemeTokens.manrope(
                        color: palette.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. 9876543290',
                        hintStyle: TextStyle(color: palette.mute),
                        prefixIcon: Icon(
                          Icons.phone_iphone_rounded,
                          color: palette.teal,
                        ),
                        filled: true,
                        fillColor: palette.field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    if (localError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        localError!,
                        style: HomeThemeTokens.manrope(
                          color: palette.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit Button
                    ElevatedButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        final phone = phoneController.text.trim();

                        if (name.isEmpty) {
                          setSheetState(
                            () => localError = 'Please enter your full name.',
                          );
                          return;
                        }
                        if (phone.length < 10) {
                          setSheetState(
                            () => localError =
                                'Please enter a valid 10-digit mobile number.',
                          );
                          return;
                        }

                        Navigator.pop(sheetCtx);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Registration request sent to Admin. Please wait for approval.',
                            ),
                            backgroundColor: AppTheme.successGreen,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Submit Registration',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
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

  void _showLoginOtpDialog(
    String phone, [
    String emailMasked = '',
    int cooldownSeconds = 60,
  ]) {
    final destination = emailMasked.isNotEmpty ? emailMasked : '+91 $phone';
    final channel =
        emailMasked.isNotEmpty ? 'registered email' : 'mobile number';

    Navigator.of(context).push(
      buildOtpPageRoute<void>(
        OtpVerificationScreen(
          destinationMasked: destination,
          destinationChannel: channel,
          initialCooldownSeconds: cooldownSeconds,
          onVerifyOtp: (otp) async {
            await ResidentAuthService.verifyLoginOtp(phone: phone, otp: otp);
            final profile = await ResidentApiService.getProfile();
            AppData.currentResident = profile;
            await TokenStorage.saveResidentProfile(profile);
            return profile;
          },
          onResendOtp: () => ResidentAuthService.requestLoginOtp(phone),
          onVerified: (otpContext, profile) {
            final residentName =
                profile['full_name'] ?? profile['name'] ?? 'Resident';
            final router = GoRouter.maybeOf(otpContext);
            if (router != null) {
              ScaffoldMessenger.of(otpContext).showSnackBar(
                SnackBar(
                  content: Text('Welcome back, $residentName!'),
                  backgroundColor: Colors.green,
                ),
              );
              router.go('/home', extra: AppData.currentResident);
            } else {
              Navigator.of(otpContext).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Welcome back, $residentName!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return AnimatedSwitcher(
      duration:
          disableAnim ? Duration.zero : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: _isRegisterMode
          ? RegisterScreen(
              key: const ValueKey('register_mode'),
              onSwitchToLogin: () => setState(() => _isRegisterMode = false),
            )
          : _buildLoginView(context, disableAnim),
    );
  }

  Widget _buildLoginView(BuildContext context, bool disableAnim) {
    final palette = _LoginPalette.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      key: const ValueKey('login_mode'),
      backgroundColor: palette.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Overlapping Hero + Main Login Card
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 52,
                      child: _buildHeroBackground(),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroContent(topInset, disableAnim),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: MotionEntrance(
                            delay: const Duration(milliseconds: 90),
                            slideOffset: const Offset(0, 0.03),
                            child: _buildLoginCard(palette, disableAnim),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Quick Demo Profiles Card
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: MotionEntrance(
                    delay: const Duration(milliseconds: 160),
                    slideOffset: const Offset(0, 0.03),
                    child: _buildQuickDemoCard(palette),
                  ),
                ),

                const SizedBox(height: 22),

                // Bottom Registration Prompt
                MotionEntrance(
                  delay: const Duration(milliseconds: 210),
                  slideOffset: const Offset(0, 0.02),
                  child: Column(
                    children: [
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'New to the PG? ',
                              style: HomeThemeTokens.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: palette.mute,
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _isRegisterMode = true),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 2,
                                ),
                                child: Text(
                                  'Create your account',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: palette.teal,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _showNewRegistrationModal(context),
                          icon: Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 15,
                            color: palette.teal,
                          ),
                          label: Text(
                            'New Registration',
                            style: HomeThemeTokens.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.teal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2231), Color(0xFF12394A)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -90,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x4D42C8B4), Color(0x0042C8B4)],
                    stops: [0.0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -60,
            bottom: -110,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x295EEAD4),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A5EEAD4),
                      spreadRadius: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroContent(double topInset, bool disableAnim) {
    final scaleAnim = Tween<double>(begin: 0.84, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    final fadeAnim = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutCubic,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(24, topInset + 32, 24, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeTransition(
            opacity: fadeAnim,
            child: ScaleTransition(
              scale: scaleAnim,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF14998B), Color(0xFF0B6B63)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8814998B),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  size: 28,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          MotionEntrance(
            delay: const Duration(milliseconds: 50),
            slideOffset: const Offset(0, 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PG Pilot',
                  style: HomeThemeTokens.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Resident portal for your PG stay',
                  style: HomeThemeTokens.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(_LoginPalette palette, bool disableAnim) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Login / Register Switcher
          _buildAuthModeSwitcher(palette, disableAnim),
          const SizedBox(height: 20),

          // Mobile Number Label & Input
          Text(
            'Mobile number',
            style: HomeThemeTokens.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 8),

          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final t = _shakeController.value;
              final dx =
                  t == 0 ? 0.0 : math.sin(t * math.pi * 4) * (1 - t) * 6.0;
              return Transform.translate(
                offset: Offset(dx, 0),
                child: child,
              );
            },
            child: _LoginFocusGlowField(
              palette: palette,
              hasError: _phoneError != null,
              child: TextFormField(
                controller: _phoneLoginController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) {
                  if (_phoneError != null) {
                    setState(() => _phoneError = null);
                  }
                },
                style: HomeThemeTokens.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.transparent,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smartphone_rounded,
                          color: _phoneError != null
                              ? palette.error
                              : palette.mute,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '+91',
                          style: HomeThemeTokens.manrope(
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 18,
                          color: palette.line,
                        ),
                      ],
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 24,
                  ),
                  hintText: '10-digit mobile number',
                  hintStyle: HomeThemeTokens.manrope(
                    color: palette.mute.withValues(alpha: 0.7),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _phoneError != null ? palette.error : palette.field,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _phoneError != null ? palette.error : palette.teal,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          AnimatedSize(
            duration: disableAnim
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _phoneError != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: palette.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _phoneError!,
                            style: HomeThemeTokens.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: palette.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 18),

          // Teal Primary CTA
          TactilePress(
            scaleDown: 0.98,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _isLoading
                    ? null
                    : [
                        BoxShadow(
                          color: palette.teal.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.teal,
                  disabledBackgroundColor: palette.teal.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: AnimatedSwitcher(
                  duration: disableAnim
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: _isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Get OTP',
                              style: HomeThemeTokens.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 19),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthModeSwitcher(_LoginPalette palette, bool disableAnim) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final halfWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedAlign(
                duration: disableAnim
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: _isRegisterMode
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: halfWidth,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x220E1A1F),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isRegisterMode = false),
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: !_isRegisterMode
                                  ? palette.teal
                                  : palette.mute,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Login',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: !_isRegisterMode
                                      ? palette.teal
                                      : palette.mute,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isRegisterMode = true),
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                              color: _isRegisterMode
                                  ? palette.teal
                                  : palette.mute,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Register',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _isRegisterMode
                                      ? palette.teal
                                      : palette.mute,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickDemoCard(_LoginPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: palette.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quick demo profiles',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeThemeTokens.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...AppData.residents.take(3).map((resident) {
            final isPending = resident['room_number'] == null ||
                resident['status'] == 'Pending';
            final name = resident['name']?.toString() ?? 'Resident';
            final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  if (isPending) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: palette.line),
                        ),
                        backgroundColor: palette.card,
                        title: Row(
                          children: [
                            Icon(
                              Icons.hourglass_top_rounded,
                              color: palette.warning,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Approval Pending',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        content: Text(
                          'Registration for $name is currently awaiting admin approval. Please wait for approval or select an active profile.',
                          style: HomeThemeTokens.manrope(
                            fontSize: 14,
                            height: 1.45,
                            color: palette.mute,
                          ),
                        ),
                        actions: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: palette.teal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                  await TokenStorage.saveResidentProfile(
                    Map<String, dynamic>.from(resident),
                  );

                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Logged in as $name!'),
                      backgroundColor: palette.teal,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  navigator.go('/home', extra: resident);
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isPending
                              ? palette.softWarning
                              : palette.softSuccess,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: HomeThemeTokens.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isPending
                                  ? palette.warning
                                  : palette.success,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HomeThemeTokens.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (isPending)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.softWarning,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: palette.warning,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Pending approval',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: palette.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Text(
                                'Active · Room ${resident['room_number'] ?? 101}',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.mute,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: palette.mute,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(_LoginPalette palette) {
    return BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: palette.line),
      boxShadow: palette.isDark
          ? const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ]
          : const [
              BoxShadow(
                color: Color(0x0A0E1A1F),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x180E1A1F),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
    );
  }
}

class _LoginFocusGlowField extends StatefulWidget {
  final _LoginPalette palette;
  final bool hasError;
  final Widget child;

  const _LoginFocusGlowField({
    required this.palette,
    required this.hasError,
    required this.child,
  });

  @override
  State<_LoginFocusGlowField> createState() => _LoginFocusGlowFieldState();
}

class _LoginFocusGlowFieldState extends State<_LoginFocusGlowField> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bgColor = widget.hasError
        ? widget.palette.softError
        : (_hasFocus ? widget.palette.card : widget.palette.field);
    return Focus(
      onFocusChange: (focused) {
        if (mounted && _hasFocus != focused) {
          setState(() => _hasFocus = focused);
        }
      },
      child: AnimatedContainer(
        duration:
            disableAnim ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _hasFocus && !widget.hasError
              ? [
                  BoxShadow(
                    color: widget.palette.teal.withValues(alpha: 0.14),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}
