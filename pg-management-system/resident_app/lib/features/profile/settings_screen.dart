import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/resident_auth_service.dart';
import '../../core/services/resident_api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isDarkMode;
  String _selectedLanguage = 'English';
  final List<String> _languages = ['English', 'Kannada', 'Hindi', 'Tamil', 'Telugu'];
  bool _rentReminders = true;
  bool _maintenanceAlerts = true;

  @override
  void initState() {
    super.initState();
    _isDarkMode = AppTheme.themeModeNotifier.value == ThemeMode.dark;
    _loadSettingsFromApi();
  }

  Future<void> _loadSettingsFromApi() async {
    try {
      final s = await ResidentApiService.getSettings();
      if (s.isNotEmpty && mounted) {
        setState(() {
          if (s['dark_mode'] is bool) {
            _isDarkMode = s['dark_mode'];
            AppTheme.toggleTheme(_isDarkMode);
          }
          if (s['language'] is String) {
            final l = s['language'].toString().toLowerCase();
            if (l == 'hi') {
              _selectedLanguage = 'Hindi';
            } else if (l == 'kn') {
              _selectedLanguage = 'Kannada';
            } else if (l == 'ta') {
              _selectedLanguage = 'Tamil';
            } else if (l == 'te') {
              _selectedLanguage = 'Telugu';
            } else {
              _selectedLanguage = 'English';
            }
          }
          if (s['rent_reminders_enabled'] is bool) {
            _rentReminders = s['rent_reminders_enabled'];
          }
          if (s['maintenance_alerts_enabled'] is bool) {
            _maintenanceAlerts = s['maintenance_alerts_enabled'];
          }
        });
      }
    } catch (e) {
      debugPrint('API getSettings error: $e');
    }
  }

  void _saveSettingsToApi() {
    String langCode = 'en';
    if (_selectedLanguage == 'Hindi') {
      langCode = 'hi';
    } else if (_selectedLanguage == 'Kannada') {
      langCode = 'kn';
    } else if (_selectedLanguage == 'Tamil') {
      langCode = 'ta';
    } else if (_selectedLanguage == 'Telugu') {
      langCode = 'te';
    }

    ResidentApiService.updateSettings({
      'dark_mode': _isDarkMode,
      'language': langCode,
      'rent_reminders_enabled': _rentReminders,
      'maintenance_alerts_enabled': _maintenanceAlerts,
    }).catchError((e) {
      debugPrint('API updateSettings error: $e');
      return <String, dynamic>{};
    });
  }

  void _showLogoutDialog() {
    final isDark = AppTheme.isDark(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.transparent),
        ),
        title: Text(
          'Confirm Logout',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : AppTheme.textDark,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of your resident account?',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ResidentAuthService.logout();
              if (mounted) {
                context.go('/login');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              minimumSize: const Size(90, 42),
            ),
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _isDarkMode = isDark;

    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;
    final dividerCol = isDark ? AppTheme.darkBorder : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: textPri,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPri),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Preferences Section
                  Text(
                    'App Preferences',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 1. Dark Mode Switch
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isDark ? Icons.dark_mode_rounded : Icons.dark_mode_outlined,
                                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.textDark,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPri), overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Text('Switch to dark visual theme', style: TextStyle(fontSize: 12, color: textSec), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch.adaptive(
                                value: _isDarkMode,
                                activeTrackColor: AppTheme.primaryBlue,
                                onChanged: (val) {
                                  setState(() => _isDarkMode = val);
                                  AppTheme.toggleTheme(val);
                                  _saveSettingsToApi();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(val ? 'Dark mode enabled' : 'Light mode enabled'),
                                      duration: const Duration(milliseconds: 900),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: dividerCol),

                        // 2. Language Dropdown
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF312E81) : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.language_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('App Language', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPri), overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Text('Choose application display language', style: TextStyle(fontSize: 12, color: textSec), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: _selectedLanguage,
                                underline: const SizedBox(),
                                borderRadius: BorderRadius.circular(14),
                                dropdownColor: cardBg,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue),
                                items: _languages.map((lang) {
                                  return DropdownMenuItem<String>(
                                    value: lang,
                                    child: Text(lang, style: TextStyle(color: isDark ? Colors.white : AppTheme.primaryBlue)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedLanguage = val);
                                    _saveSettingsToApi();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Language changed to $val'),
                                        duration: const Duration(milliseconds: 900),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Push Notifications Section
                  Text(
                    'Push Notifications',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textPri,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.notifications_active_outlined,
                                color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Rent Reminders',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPri),
                            ),
                            subtitle: Text(
                              'Receive alerts before rent due...',
                              style: TextStyle(fontSize: 12, color: textSec),
                            ),
                            value: _rentReminders,
                            activeTrackColor: AppTheme.primaryBlue,
                            onChanged: (val) {
                              setState(() => _rentReminders = val);
                              _saveSettingsToApi();
                            },
                          ),
                          Divider(height: 1, color: dividerCol),
                          SwitchListTile.adaptive(
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.campaign_outlined, color: Color(0xFFD97706), size: 20),
                            ),
                            title: Text(
                              'Maintenance Alerts',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPri),
                            ),
                            subtitle: Text(
                              'Updates on complaint resolution...',
                              style: TextStyle(fontSize: 12, color: textSec),
                            ),
                            value: _maintenanceAlerts,
                            activeTrackColor: AppTheme.primaryBlue,
                            onChanged: (val) {
                              setState(() => _maintenanceAlerts = val);
                              _saveSettingsToApi();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // UPI Package POC Card
                  Material(
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: borderCol),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.science_rounded, color: AppTheme.primaryBlue, size: 20),
                      ),
                      title: Text(
                        'UPI Package POC (flutter_upi_india)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPri),
                      ),
                      subtitle: Text(
                        'Evaluate package-based ₹1 intent vs bank limits',
                        style: TextStyle(fontSize: 11.5, color: textSec),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      onTap: () => context.push('/poc-upi-india'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: borderCol),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.biotech_rounded, color: Color(0xFF0D9488), size: 20),
                      ),
                      title: Text(
                        'UPI Pay Package POC (upi_pay)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPri),
                      ),
                      subtitle: Text(
                        'Evaluate drenther/upi_pay with GPay, PhonePe & Navi',
                        style: TextStyle(fontSize: 11.5, color: textSec),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      onTap: () => context.push('/poc-upi-pay'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Red Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showLogoutDialog,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
