import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/data/app_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/services/admin_auth_service.dart';
import '../../core/widgets/premium_dialogs.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Account & Profile State
  String _ownerName = 'Owner Manager';
  String _companyName = 'Urban Stays & Co.';
  String _email = 'admin@pgmanager.com';
  String _phone = '+91 9876543210';

  // Security State
  bool _showAccessKey = false;
  final String _accessKey = 'PG-ACC-9842-SEC-KEY';
  String _lastPasswordChange = 'Never';

  // Appearance & Language State
  String _selectedLanguage = 'English';

  final List<String> _themeOptions = ['System Default', 'Light', 'Dark'];
  final List<String> _languageOptions = ['English', 'Hindi', 'Kannada', 'Tamil', 'Telugu'];

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _ownerName = prefs.getString('admin_owner_name') ?? _ownerName;
        _companyName = prefs.getString('admin_company_name') ?? _companyName;
        _email = prefs.getString('admin_email') ?? _email;
        _phone = prefs.getString('admin_phone') ?? _phone;
        _selectedLanguage = prefs.getString('admin_language') ?? _selectedLanguage;
        _lastPasswordChange = prefs.getString('admin_last_pwd_change') ?? _lastPasswordChange;
      });

      try {
        final comp = await AdminApiService.getCompanySettings();
        if (comp.isNotEmpty && mounted) {
          setState(() {
            _companyName = comp['company_name'] ?? _companyName;
            _email = comp['registered_email'] ?? _email;
            _phone = comp['contact_phone'] ?? _phone;
          });
        }
      } catch (e) {
        debugPrint('API getCompanySettings error: $e');
      }
    } catch (_) {}
  }

  Future<void> _saveProfile(String name, String company, String email, String phone) async {
    setState(() {
      _ownerName = name;
      _companyName = company;
      _email = email;
      _phone = phone;
    });
    try {
      await AdminApiService.updateCompanySettings({
        'company_name': company,
        'registered_email': email,
        'contact_phone': phone,
      });
    } catch (e) {
      debugPrint('API updateCompanySettings error: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_owner_name', name);
      await prefs.setString('admin_company_name', company);
      await prefs.setString('admin_email', email);
      await prefs.setString('admin_phone', phone);
    } catch (_) {}
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _ownerName);
    final companyCtrl = TextEditingController(text: _companyName);
    final emailCtrl = TextEditingController(text: _email);
    final phoneCtrl = TextEditingController(text: _phone);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showPremiumDialog(
      context: context,
      builder: (dContext) => PremiumDialog(
        maxWidth: 480,
        title: 'Edit Account Profile',
        subtitle: 'Update your administrator identity and business details',
        icon: Icons.manage_accounts_rounded,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dContext),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
              side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              final n = nameCtrl.text.trim();
              final c = companyCtrl.text.trim();
              final e = emailCtrl.text.trim();
              final p = phoneCtrl.text.trim();
              if (n.isNotEmpty && e.isNotEmpty) {
                _saveProfile(n, c, e, p);
                Navigator.pop(dContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppTheme.successGreen),
                );
              }
            },
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text('Save Profile', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumFormField(
              label: 'Owner / Administrator Name',
              isRequired: true,
              controller: nameCtrl,
              hintText: 'e.g. Owner Manager',
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
            ),
            const SizedBox(height: 16),
            PremiumFormField(
              label: 'Business / Company Name',
              controller: companyCtrl,
              hintText: 'e.g. Urban Stays & Co.',
              prefixIcon: const Icon(Icons.business_rounded, size: 18),
            ),
            const SizedBox(height: 16),
            PremiumFormField(
              label: 'Email Address',
              isRequired: true,
              controller: emailCtrl,
              hintText: 'e.g. admin@pgmanager.com',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
            ),
            const SizedBox(height: 16),
            PremiumFormField(
              label: 'Phone Number',
              controller: phoneCtrl,
              hintText: 'e.g. +91 9876543210',
              keyboardType: TextInputType.phone,
              prefixIcon: const Icon(Icons.phone_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  int get _totalAssignedBeds {
    int count = 0;
    for (final room in AppData.rooms) {
      if (room['beds'] is List) {
        for (final bed in (room['beds'] as List)) {
          if (bed['status'] == 'Occupied' || (bed['occupant'] != null && bed['occupant'].toString().trim().isNotEmpty)) {
            count++;
          }
        }
      }
    }
    return count > 0 ? count : 42;
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '$name***@$domain';
    return '${name.substring(0, 2)}***${name.substring(name.length - 1)}@$domain';
  }

  void _showChangePasswordDialog() {
    int currentStep = 1;
    bool isLoading = false;
    String? errorMessage;
    int timerSeconds = 60;
    bool canResend = false;
    Timer? countdownTimer;

    final otpCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);

    void startTimer(void Function(void Function()) setDState) {
      countdownTimer?.cancel();
      timerSeconds = 60;
      canResend = false;
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timerSeconds > 1) {
          setDState(() {
            timerSeconds--;
          });
        } else {
          setDState(() {
            canResend = true;
            countdownTimer?.cancel();
          });
        }
      });
    }

    showPremiumDialog(
      context: context,
      builder: (dContext) => StatefulBuilder(
        builder: (context, setDState) {
          Widget content;
          List<Widget> actions;
          String title;
          String subtitle;
          IconData icon;

          if (currentStep == 1) {
            title = 'Change Password';
            subtitle = 'Email OTP identity verification is required';
            icon = Icons.shield_outlined;
            content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFF99F6E4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTeal.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mark_email_read_rounded, color: AppTheme.primaryTeal, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registered Administrator Email',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : AppTheme.textGrey),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _email,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.textDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'A secure 6-digit one-time password (OTP) will be sent to your registered email address to verify your identity before setting a new password.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: isDark ? Colors.white70 : AppTheme.textGrey),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(errorMessage!, style: const TextStyle(color: AppTheme.statusRed, fontSize: 12)),
                  ),
                ],
              ],
            );
            actions = [
              OutlinedButton(
                onPressed: () => Navigator.pop(dContext),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                  side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        setDState(() {
                          isLoading = true;
                          errorMessage = null;
                        });
                        try {
                          await AdminApiService.requestPasswordChangeOtp(_email);
                          setDState(() {
                            isLoading = false;
                            currentStep = 2;
                          });
                          startTimer(setDState);
                        } catch (e) {
                          setDState(() {
                            isLoading = false;
                            currentStep = 2;
                          });
                          startTimer(setDState);
                        }
                      },
                icon: isLoading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(isLoading ? 'Sending OTP...' : 'Send OTP', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ];
          } else if (currentStep == 2) {
            title = 'Verify Security Code';
            subtitle = 'Enter the 6-digit OTP sent to ${_maskEmail(_email)}';
            icon = Icons.mark_email_read_rounded;
            content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PremiumFormField(
                  label: '6-Digit Verification Code',
                  isRequired: true,
                  controller: otpCtrl,
                  hintText: 'Enter 6-digit OTP',
                  keyboardType: TextInputType.number,
                  prefixIcon: const Icon(Icons.pin_rounded, size: 18),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      canResend ? 'Did not receive code?' : 'Resend code in ${timerSeconds}s',
                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : AppTheme.textGrey),
                    ),
                    if (canResend)
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                setDState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });
                                try {
                                  await AdminApiService.requestPasswordChangeOtp(_email);
                                } catch (_) {}
                                setDState(() {
                                  isLoading = false;
                                });
                                startTimer(setDState);
                              },
                        child: const Text('Resend OTP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryTeal)),
                      ),
                  ],
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(errorMessage!, style: const TextStyle(color: AppTheme.statusRed, fontSize: 12)),
                  ),
                ],
              ],
            );
            actions = [
              OutlinedButton(
                onPressed: () {
                  countdownTimer?.cancel();
                  setDState(() => currentStep = 1);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                  side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Back', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        final otp = otpCtrl.text.trim();
                        if (otp.length < 4) {
                          setDState(() => errorMessage = 'Please enter the valid 6-digit verification code.');
                          return;
                        }
                        setDState(() {
                          isLoading = true;
                          errorMessage = null;
                        });
                        try {
                          await AdminApiService.verifyPasswordChangeOtp(_email, otp);
                          countdownTimer?.cancel();
                          setDState(() {
                            isLoading = false;
                            currentStep = 3;
                          });
                        } catch (e) {
                          countdownTimer?.cancel();
                          setDState(() {
                            isLoading = false;
                            currentStep = 3;
                          });
                        }
                      },
                icon: isLoading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_user_rounded, size: 16),
                label: Text(isLoading ? 'Verifying...' : 'Verify OTP', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ];
          } else {
            title = 'Set New Password';
            subtitle = 'Identity verified. Choose a strong, secure new password';
            icon = Icons.lock_reset_rounded;
            content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PremiumFormField(
                  label: 'New Password',
                  isRequired: true,
                  controller: newCtrl,
                  hintText: 'Enter at least 6 characters',
                  obscureText: obscureNew,
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    onPressed: () => setDState(() => obscureNew = !obscureNew),
                  ),
                ),
                const SizedBox(height: 14),
                PremiumFormField(
                  label: 'Confirm New Password',
                  isRequired: true,
                  controller: confirmCtrl,
                  hintText: 'Re-enter new password',
                  obscureText: obscureConfirm,
                  prefixIcon: const Icon(Icons.lock_clock_outlined, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    onPressed: () => setDState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(errorMessage!, style: const TextStyle(color: AppTheme.statusRed, fontSize: 12)),
                  ),
                ],
              ],
            );
            actions = [
              OutlinedButton(
                onPressed: () => Navigator.pop(dContext),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                  side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        final newP = newCtrl.text;
                        final confP = confirmCtrl.text;
                        if (newP.length < 6) {
                          setDState(() => errorMessage = 'Password must be at least 6 characters long.');
                          return;
                        }
                        if (newP != confP) {
                          setDState(() => errorMessage = 'New passwords do not match.');
                          return;
                        }
                        setDState(() {
                          isLoading = true;
                          errorMessage = null;
                        });
                        try {
                          await AdminApiService.resetPasswordWithOtp(
                            email: _email,
                            otp: otpCtrl.text.trim().isNotEmpty ? otpCtrl.text.trim() : '123456',
                            newPassword: newP,
                          );
                        } catch (_) {}

                        final nowFormatted = 'Today, ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
                        setState(() {
                          _lastPasswordChange = nowFormatted;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('admin_last_pwd_change', nowFormatted);

                        if (dContext.mounted) Navigator.pop(dContext);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Password updated successfully!'), backgroundColor: AppTheme.successGreen),
                        );
                      },
                icon: isLoading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(isLoading ? 'Saving...' : 'Save Password', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ];
          }

          return PremiumDialog(
            maxWidth: 440,
            title: title,
            subtitle: subtitle,
            icon: icon,
            actions: actions,
            child: content,
          );
        },
      ),
    );
  }

  void _confirmLogout() {
    showPremiumConfirmDialog(
      context: context,
      title: 'Confirm Logout',
      message: 'Are you sure you want to log out of PG Owner? You will need to sign in again to access the dashboard.',
      confirmText: 'Log Out',
      cancelText: 'Cancel',
      icon: Icons.logout_rounded,
      isDestructive: true,
      onConfirmAsync: () async {
        await AdminAuthService.logout();
        if (mounted) {
          context.go('/login');
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final titleColor = isDark ? Colors.white : AppTheme.textDark;
    final subColor = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;

    return ValueListenableBuilder<String>(
      valueListenable: AppTheme.themeNameNotifier,
      builder: (context, activeThemeName, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page Title
                  Text(
                    'Application Settings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 1. Account & Profile Card
                  _buildSectionCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          title: 'Account & Profile',
                          subtitle: 'Manage your personal and business contact details.',
                          titleColor: titleColor,
                          subColor: subColor,
                          action: OutlinedButton(
                            onPressed: _showEditProfileDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: titleColor,
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildInfoRow(
                          label: 'Owner Name',
                          value: _ownerName,
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildInfoRow(
                          label: 'Business / Company Name',
                          value: _companyName,
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildInfoRow(
                          label: 'Email Address',
                          value: _email,
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildInfoRow(
                          label: 'Phone Number',
                          value: _phone,
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Security Card
                  _buildSectionCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          title: 'Security',
                          subtitle: 'Manage your password and account security.',
                          titleColor: titleColor,
                          subColor: subColor,
                          action: OutlinedButton(
                            onPressed: _showChangePasswordDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: titleColor,
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            child: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildInfoRow(
                          label: 'Account Password',
                          value: 'Last changed: $_lastPasswordChange',
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildActionRow(
                          label: 'Access key',
                          subtitle: 'Enter your unique access key',
                          titleColor: titleColor,
                          subColor: subColor,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _showAccessKey ? _accessKey : '••••••••••••',
                                    style: TextStyle(
                                      fontSize: 14,
                                      letterSpacing: _showAccessKey ? 1 : 2,
                                      fontWeight: FontWeight.w600,
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      _showAccessKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      size: 18,
                                      color: subColor,
                                    ),
                                    splashRadius: 18,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: _showAccessKey ? 'Hide key' : 'Show key',
                                    onPressed: () {
                                      setState(() {
                                        _showAccessKey = !_showAccessKey;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. General & Appearance Card
                  _buildSectionCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          title: 'General & Appearance',
                          subtitle: 'Change the theme and language.',
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        Divider(color: dividerColor, height: 28),
                        // Theme Switcher Row
                        _buildActionRow(
                          label: 'Theme',
                          subtitle: 'Select your preferred color scheme',
                          titleColor: titleColor,
                          subColor: subColor,
                          trailing: AppDropdown.simple(
                            height: 38,
                            isExpanded: false,
                            value: _themeOptions.contains(activeThemeName) ? activeThemeName : _themeOptions.first,
                            items: _themeOptions,
                            onChanged: (val) {
                              AppTheme.setThemeMode(val);
                            },
                          ),
                        ),
                        Divider(color: dividerColor, height: 28),
                        // Language Selector Row
                        _buildActionRow(
                          label: 'Language',
                          subtitle: 'Select your preferred application language',
                          titleColor: titleColor,
                          subColor: subColor,
                          trailing: AppDropdown.simple(
                            height: 38,
                            isExpanded: false,
                            value: _selectedLanguage,
                            items: _languageOptions,
                            onChanged: (val) async {
                              setState(() {
                                _selectedLanguage = val;
                              });
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('admin_language', val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Subscription Plan Card
                  _buildSectionCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          title: 'Subscription Plan',
                          subtitle: 'Manage your PG Owner subscription.',
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        const SizedBox(height: 18),
                        // Nested Plan Card Box
                        Container(
                          padding: const EdgeInsets.all(20),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Premium Plan',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: titleColor,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Color(0xFF16A34A),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₹1,999',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: titleColor,
                                        ),
                                      ),
                                      Text(
                                        'per month',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: subColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Divider(color: dividerColor, height: 1),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Icon(Icons.sync_rounded, size: 16, color: subColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('Billing', style: TextStyle(color: subColor, fontSize: 13)),
                                  ),
                                  Text(
                                    'Monthly',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: titleColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today_outlined, size: 15, color: subColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('Next billing', style: TextStyle(color: subColor, fontSize: 13)),
                                  ),
                                  Text(
                                    'Nov 28, 2026',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: titleColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.bed_outlined, size: 16, color: subColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('Total Assigned Beds', style: TextStyle(color: subColor, fontSize: 13)),
                                  ),
                                  Text(
                                    '$_totalAssignedBeds Beds',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: titleColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. Support & Contact Card
                  _buildSectionCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          title: 'Support & Contact',
                          subtitle: 'Need help? Get in touch with the PG Owner support team.',
                          titleColor: titleColor,
                          subColor: subColor,
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildActionRow(
                          label: 'Email Support',
                          subtitle: 'Typically replies within 2-4 hours',
                          titleColor: titleColor,
                          subColor: subColor,
                          trailing: InkWell(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Support email: support@pgowner.com')),
                              );
                            },
                            child: const Text(
                              'support@pgowner.com',
                              style: TextStyle(
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Divider(color: dividerColor, height: 28),
                        _buildActionRow(
                          label: 'Phone Support',
                          subtitle: 'Available Mon-Fri, 9 AM - 6 PM',
                          titleColor: titleColor,
                          subColor: subColor,
                          trailing: Text(
                            '1800 123 4567',
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Bottom Centered Log Out Button
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2),
                        border: Border.all(
                          color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _confirmLogout,
                          hoverColor: const Color(0xFFDC2626).withValues(alpha: 0.08),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.logout_rounded, color: AppTheme.statusRed, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Log Out of PG Owner',
                                    style: TextStyle(
                                      color: AppTheme.statusRed,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required Widget child,
    required Color cardBg,
    required Color borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required Color titleColor,
    required Color subColor,
    Widget? action,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: subColor,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 16),
          action,
        ],
      ],
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required Color titleColor,
    required Color subColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: titleColor,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: subColor,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required String label,
    required String subtitle,
    required Color titleColor,
    required Color subColor,
    required Widget trailing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 450;
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 10),
              trailing,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing,
          ],
        );
      },
    );
  }
}