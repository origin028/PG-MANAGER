import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/services/resident_auth_service.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late bool _isDarkMode;
  String _selectedLanguage = 'English';
  final List<String> _languages = [
    'English',
    'Kannada',
    'Hindi',
    'Tamil',
    'Telugu',
  ];
  bool _rentReminders = true;
  bool _maintenanceAlerts = true;

  late final AnimationController _entranceController;
  bool _animationStarted = false;

  @override
  void initState() {
    super.initState();
    _isDarkMode = AppTheme.themeModeNotifier.value == ThemeMode.dark;
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _loadSettingsFromApi();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
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
    final isDark = HomeThemeTokens.isDark(context);
    final dialogBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final borderCol = HomeThemeTokens.border(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderCol),
        ),
        title: Text(
          'Confirm Logout',
          style: HomeThemeTokens.manrope(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: textPri,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of your resident account?',
          style: HomeThemeTokens.manrope(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: textSec,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: HomeThemeTokens.manrope(
                color: textSec,
                fontWeight: FontWeight.w700,
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
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              minimumSize: const Size(92, 42),
            ),
            child: Text(
              'Log Out',
              style: HomeThemeTokens.manrope(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (GoRouter.maybeOf(context) != null) {
      context.go('/menu');
    }
  }

  String _getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return 'R';
  }

  Map<String, dynamic> _resolveResidentData() {
    final savedProfile = TokenStorage.residentProfile;
    if (savedProfile != null &&
        savedProfile.isNotEmpty &&
        AppData.currentResident['phone'] == AppData.residents.first['phone'] &&
        AppData.currentResident['room_number'] == null) {
      return savedProfile;
    }
    return AppData.currentResident;
  }

  Widget _staggeredEntrance({
    required double begin,
    required double end,
    required Widget child,
  }) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        begin.clamp(0.0, 0.96),
        end.clamp(0.05, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, inner) {
        final t = anim.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: inner,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = HomeThemeTokens.isDark(context);
    _isDarkMode = isDark;

    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final dividerCol =
        isDark ? HomeThemeTokens.darkBorder : const Color(0xFFF0F4F3);

    final resident = _resolveResidentData();
    final residentInfo =
        (resident['resident_info'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final stayDetails =
        (resident['stay_details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final kycDetails =
        (resident['kyc_details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final rawName =
        residentInfo['full_name'] ??
        resident['full_name'] ??
        resident['name'] ??
        'Resident';
    final name = rawName.toString().trim().isNotEmpty
        ? rawName.toString().trim()
        : 'Resident';

    final rawProperty =
        stayDetails['property_name'] ??
        resident['property_name'] ??
        resident['property'];
    final propertyName =
        (rawProperty != null && rawProperty.toString().trim().isNotEmpty)
            ? rawProperty.toString().trim()
            : 'BNR Luxury PG';

    final rawRoom =
        stayDetails['room_number'] ?? resident['room_number'] ?? resident['room'];
    final room = (rawRoom != null && rawRoom.toString().trim().isNotEmpty)
        ? rawRoom.toString().trim()
        : '101';

    final kycStr = (kycDetails['kyc_status'] ??
            resident['kyc'] ??
            resident['kyc_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final isVerified = kycStr == 'verified' || kycStr == 'approved';

    final cardShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x20000000) : const Color(0x0A0E1A1F),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ];

    final logoutBorderCol =
        isDark ? const Color(0xFF6B3A37) : const Color(0xFFF8C9C4);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            // ----------------------------------------------------------------
            // 1. TOP HEADER BAR
            // ----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Row(
                    children: [
                      _InteractivePress(
                        onTap: _handleBack,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: borderCol, width: 1),
                            boxShadow: cardShadow,
                          ),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: textPri,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Settings',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeThemeTokens.manrope(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: textPri,
                          ),
                        ),
                      ),
                      const SizedBox(width: 42),
                    ],
                  ),
                ),
              ),
            ),

            // ----------------------------------------------------------------
            // 2. SCROLLABLE CONTENT
            // ----------------------------------------------------------------
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ----------------------------------------------------
                        // COMPACT RESIDENT IDENTITY SUMMARY CARD
                        // ----------------------------------------------------
                        _staggeredEntrance(
                          begin: 0.04,
                          end: 0.42,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderCol, width: 1),
                              boxShadow: cardShadow,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2B5A72)
                                        : HomeThemeTokens.lightNavy,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _getInitials(name),
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: textPri,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$propertyName · Room $room',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: textSec,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isVerified
                                        ? HomeThemeTokens.successBg(context)
                                        : HomeThemeTokens.warningBg(context),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isVerified
                                            ? Icons.check_rounded
                                            : Icons.hourglass_top_rounded,
                                        size: 13,
                                        color: isVerified
                                            ? HomeThemeTokens.success(context)
                                            : HomeThemeTokens.warning(context),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'KYC',
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: isVerified
                                              ? HomeThemeTokens.success(context)
                                              : HomeThemeTokens.warning(
                                                  context,
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
                        const SizedBox(height: 22),

                        // ----------------------------------------------------
                        // APP PREFERENCES SECTION
                        // ----------------------------------------------------
                        _staggeredEntrance(
                          begin: 0.14,
                          end: 0.54,
                          child: _buildSectionHeading(
                            title: 'App Preferences',
                            tealCol: tealCol,
                            textSec: textSec,
                          ),
                        ),
                        const SizedBox(height: 10),

                        _staggeredEntrance(
                          begin: 0.20,
                          end: 0.66,
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderCol, width: 1),
                              boxShadow: cardShadow,
                            ),
                            child: Column(
                              children: [
                                // 1. Dark Mode Switch Row
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color:
                                              HomeThemeTokens.foodBg(context),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isDark
                                              ? Icons.dark_mode_rounded
                                              : Icons.dark_mode_outlined,
                                          color: HomeThemeTokens.foodIcon(
                                            context,
                                          ),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Dark Mode',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: HomeThemeTokens.manrope(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                                color: textPri,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Switch to dark visual theme',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: textSec,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildSwitch(
                                        value: _isDarkMode,
                                        isDark: isDark,
                                        tealCol: tealCol,
                                        onChanged: (val) {
                                          setState(() => _isDarkMode = val);
                                          AppTheme.toggleTheme(val);
                                          _saveSettingsToApi();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                val
                                                    ? 'Dark mode enabled'
                                                    : 'Light mode enabled',
                                              ),
                                              duration: const Duration(
                                                milliseconds: 900,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                _buildInsetDivider(dividerCol),

                                // 2. App Language Selector Row
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: softTealCol,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.language_rounded,
                                          color: tealCol,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'App Language',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: HomeThemeTokens.manrope(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                                color: textPri,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Choose application display language',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: textSec,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              HomeThemeTokens.foodBg(context),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: _selectedLanguage,
                                            isDense: true,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            dropdownColor: cardBg,
                                            icon: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 17,
                                              color: HomeThemeTokens.foodIcon(
                                                context,
                                              ),
                                            ),
                                            style: HomeThemeTokens.manrope(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.5,
                                              color: HomeThemeTokens.foodIcon(
                                                context,
                                              ),
                                            ),
                                            items: _languages.map((lang) {
                                              return DropdownMenuItem<String>(
                                                value: lang,
                                                child: Text(
                                                  lang,
                                                  style:
                                                      HomeThemeTokens.manrope(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                    color: textPri,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            selectedItemBuilder: (context) {
                                              return _languages.map((lang) {
                                                return Center(
                                                  child: Text(
                                                    lang,
                                                    style:
                                                        HomeThemeTokens.manrope(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12.5,
                                                      color: HomeThemeTokens
                                                          .foodIcon(context),
                                                    ),
                                                  ),
                                                );
                                              }).toList();
                                            },
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(
                                                  () => _selectedLanguage = val,
                                                );
                                                _saveSettingsToApi();
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Language changed to $val',
                                                    ),
                                                    duration: const Duration(
                                                      milliseconds: 900,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
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
                        const SizedBox(height: 22),

                        // ----------------------------------------------------
                        // PUSH NOTIFICATIONS SECTION
                        // ----------------------------------------------------
                        _staggeredEntrance(
                          begin: 0.28,
                          end: 0.72,
                          child: _buildSectionHeading(
                            title: 'Push Notifications',
                            tealCol: tealCol,
                            textSec: textSec,
                          ),
                        ),
                        const SizedBox(height: 10),

                        _staggeredEntrance(
                          begin: 0.34,
                          end: 0.80,
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderCol, width: 1),
                              boxShadow: cardShadow,
                            ),
                            child: Column(
                              children: [
                                _buildToggleRow(
                                  icon: Icons.notifications_none_rounded,
                                  iconBg: HomeThemeTokens.foodBg(context),
                                  iconColor: HomeThemeTokens.foodIcon(context),
                                  title: 'Rent Reminders',
                                  subtitle: 'Receive alerts before rent due date',
                                  value: _rentReminders,
                                  isDark: isDark,
                                  tealCol: tealCol,
                                  textPri: textPri,
                                  textSec: textSec,
                                  onChanged: (val) {
                                    setState(() => _rentReminders = val);
                                    _saveSettingsToApi();
                                  },
                                ),
                                _buildInsetDivider(dividerCol),
                                _buildToggleRow(
                                  icon: Icons.campaign_outlined,
                                  iconBg: HomeThemeTokens.warningBg(context),
                                  iconColor: HomeThemeTokens.warning(context),
                                  title: 'Maintenance Alerts',
                                  subtitle: 'Updates on complaint resolution',
                                  value: _maintenanceAlerts,
                                  isDark: isDark,
                                  tealCol: tealCol,
                                  textPri: textPri,
                                  textSec: textSec,
                                  onChanged: (val) {
                                    setState(() => _maintenanceAlerts = val);
                                    _saveSettingsToApi();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // ----------------------------------------------------
                        // EXISTING PAYMENT EVALUATION POC TOOLS
                        // ----------------------------------------------------
                        _staggeredEntrance(
                          begin: 0.42,
                          end: 0.86,
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderCol, width: 1),
                              boxShadow: cardShadow,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(19),
                              child: Column(
                                children: [
                                  _buildNavRow(
                                    icon: Icons.science_rounded,
                                    iconBg: HomeThemeTokens.foodBg(context),
                                    iconColor:
                                        HomeThemeTokens.foodIcon(context),
                                    title: 'UPI Package POC (flutter_upi_india)',
                                    subtitle:
                                        'Evaluate package-based ₹1 intent vs bank limits',
                                    textPri: textPri,
                                    textSec: textSec,
                                    onTap: () =>
                                        context.push('/poc-upi-india'),
                                  ),
                                  _buildInsetDivider(dividerCol),
                                  _buildNavRow(
                                    icon: Icons.biotech_rounded,
                                    iconBg: softTealCol,
                                    iconColor: tealCol,
                                    title: 'UPI Pay Package POC (upi_pay)',
                                    subtitle:
                                        'Evaluate drenther/upi_pay with GPay, PhonePe & Navi',
                                    textPri: textPri,
                                    textSec: textSec,
                                    onTap: () => context.push('/poc-upi-pay'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ----------------------------------------------------
                        // LOG OUT BUTTON (SOFT ROSE PILL)
                        // ----------------------------------------------------
                        _staggeredEntrance(
                          begin: 0.48,
                          end: 0.94,
                          child: _InteractivePress(
                            child: Container(
                              decoration: BoxDecoration(
                                color: HomeThemeTokens.errorBg(context),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: logoutBorderCol,
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(15),
                                child: InkWell(
                                  onTap: _showLogoutDialog,
                                  borderRadius: BorderRadius.circular(15),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14.5,
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.logout_rounded,
                                          size: 18.5,
                                          color:
                                              HomeThemeTokens.error(context),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Log Out',
                                          style: HomeThemeTokens.manrope(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color:
                                                HomeThemeTokens.error(context),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeading({
    required String title,
    required Color tealCol,
    required Color textSec,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: tealCol,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HomeThemeTokens.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.25,
                color: textSec,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsetDivider(Color dividerCol) {
    return Padding(
      padding: const EdgeInsets.only(left: 70),
      child: Container(height: 1, color: dividerCol),
    );
  }

  Widget _buildSwitch({
    required bool value,
    required bool isDark,
    required Color tealCol,
    required ValueChanged<bool> onChanged,
  }) {
    return Switch.adaptive(
      value: value,
      activeTrackColor: tealCol,
      inactiveTrackColor:
          isDark ? const Color(0xFF404F59) : const Color(0xFFD5DCDA),
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      onChanged: onChanged,
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required bool isDark,
    required Color tealCol,
    required Color textPri,
    required Color textSec,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildSwitch(
                value: value,
                isDark: isDark,
                tealCol: tealCol,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textPri,
    required Color textSec,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: textSec,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tactile press scale feedback wrapper respecting reduced motion.
class _InteractivePress extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _InteractivePress({
    this.onTap,
    required this.child,
  });

  @override
  State<_InteractivePress> createState() => _InteractivePressState();
}

class _InteractivePressState extends State<_InteractivePress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final scaled = AnimatedScale(
      scale: (_pressed && !disableAnim) ? 0.97 : 1.0,
      duration: disableAnim ? Duration.zero : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    if (widget.onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: scaled,
      );
    }

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: scaled,
    );
  }
}
