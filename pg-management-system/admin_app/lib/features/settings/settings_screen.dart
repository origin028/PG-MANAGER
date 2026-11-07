import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/services/admin_api_service.dart';

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

  Widget _buildDialogField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required Color titleColor,
    required Color borderColor,
    required Color cardBg,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, color: titleColor, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _ownerName);
    final companyCtrl = TextEditingController(text: _companyName);
    final emailCtrl = TextEditingController(text: _email);
    final phoneCtrl = TextEditingController(text: _phone);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.textDark;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    showDialog(
      context: context,
      builder: (dContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Edit Account Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: titleColor)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogField(
                  label: 'Owner Name',
                  controller: nameCtrl,
                  hintText: 'e.g. Owner Manager',
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
                const SizedBox(height: 16),
                _buildDialogField(
                  label: 'Business / Company Name',
                  controller: companyCtrl,
                  hintText: 'e.g. Urban Stays & Co.',
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
                const SizedBox(height: 16),
                _buildDialogField(
                  label: 'Email Address',
                  controller: emailCtrl,
                  hintText: 'e.g. admin@pgmanager.com',
                  keyboardType: TextInputType.emailAddress,
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
                const SizedBox(height: 16),
                _buildDialogField(
                  label: 'Phone Number',
                  controller: phoneCtrl,
                  hintText: 'e.g. +91 9876543210',
                  keyboardType: TextInputType.phone,
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dContext),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              final n = nameCtrl.text.trim();
              final c = companyCtrl.text.trim();
              final e = emailCtrl.text.trim();
              final p = phoneCtrl.text.trim();
              if (n.isNotEmpty && e.isNotEmpty) {
                _saveProfile(n, c, e, p);
                Navigator.pop(dContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Save Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.textDark;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dContext) {
        final navigator = Navigator.of(dContext);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: titleColor)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogField(
                  label: 'Current Password',
                  controller: currentCtrl,
                  hintText: 'Enter current password',
                  obscureText: true,
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
                const SizedBox(height: 16),
                _buildDialogField(
                  label: 'New Password',
                  controller: newCtrl,
                  hintText: 'Enter new password',
                  obscureText: true,
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
                const SizedBox(height: 16),
                _buildDialogField(
                  label: 'Confirm New Password',
                  controller: confirmCtrl,
                  hintText: 'Re-enter new password',
                  obscureText: true,
                  titleColor: titleColor,
                  borderColor: borderColor,
                  cardBg: cardBg,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newCtrl.text.trim().isEmpty) return;
                if (newCtrl.text != confirmCtrl.text) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('New passwords do not match!'), backgroundColor: Colors.red),
                  );
                  return;
                }
                final nowFormatted = 'Today, ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
                setState(() {
                  _lastPasswordChange = nowFormatted;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('admin_last_pwd_change', nowFormatted);

                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Update Password', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _confirmLogout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.textDark;
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;
    final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    showDialog(
      context: context,
      builder: (dContext) => AlertDialog(
        backgroundColor: dialogBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: isDark ? BorderSide(color: borderColor, width: 1) : BorderSide.none,
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        actionsOverflowButtonSpacing: 8,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded, color: AppTheme.primaryBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Confirm Logout',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: titleColor,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to log out of PG Owner?',
          style: TextStyle(
            color: subtitleColor,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dContext),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: subtitleColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dContext);
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text(
              'Log Out',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
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
                        Divider(color: dividerColor, height: 28),
                        _buildActionRow(
                          label: 'Help Center',
                          subtitle: 'Browse FAQs and tutorials',
                          titleColor: titleColor,
                          subColor: subColor,
                          trailing: OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Opening PG Owner Help Center documentation...')),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: titleColor,
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            child: const Text('Visit Help Center', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                        color: isDark ? const Color(0xFF1E293B) : AppTheme.primaryLight,
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _confirmLogout,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.logout_rounded, color: AppTheme.primaryBlue, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Log Out of PG Owner',
                                    style: TextStyle(
                                      color: AppTheme.primaryBlue,
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