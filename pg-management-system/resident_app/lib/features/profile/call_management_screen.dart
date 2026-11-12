import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class CallManagementScreen extends StatefulWidget {
  const CallManagementScreen({super.key});

  @override
  State<CallManagementScreen> createState() => _CallManagementScreenState();
}

class _CallManagementScreenState extends State<CallManagementScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _managerName = 'Rajesh Kumar';
  String _managerTitle = 'PG Owner • Available 8 AM - 10 PM';
  String _managerPhone = '9876543210';
  String _managerWhatsApp = '919876543210';

  String _caretakerName = 'Gate Security & Caretaker';
  String _caretakerTitle = '24/7 Desk';
  String _caretakerPhone = '9876543211';

  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _loadPropertyContacts();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _triggerEntranceAnimation() {
    if (!mounted) return;
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) {
      _entranceController.value = 1.0;
    } else {
      _entranceController.forward(from: 0.0);
    }
  }

  Future<void> _loadPropertyContacts() async {
    setState(() => _isLoading = true);
    try {
      final data = await ResidentApiService.getPropertyContacts();
      final contacts = data['contacts'] as List<dynamic>?;
      if (contacts != null && contacts.isNotEmpty) {
        for (var c in contacts) {
          final role = (c['role'] ?? '').toString().toUpperCase();
          final phone = (c['phone'] ?? '').toString();
          final name = (c['name'] ?? '').toString();
          final wa = (c['whatsapp_number'] ?? phone).toString();
          final timing = (c['timing_hours'] ?? '').toString();

          if (role.contains('MANAGER') || role.contains('OWNER')) {
            _managerName = name.isNotEmpty ? name : _managerName;
            _managerPhone = phone.isNotEmpty ? phone : _managerPhone;
            _managerWhatsApp = wa.isNotEmpty ? wa : _managerWhatsApp;
            if (timing.isNotEmpty) {
              _managerTitle = 'PG Owner • $timing';
            }
          } else if (role.contains('CARETAKER') ||
              role.contains('WARDEN') ||
              role.contains('SECURITY')) {
            _caretakerName =
                name.isNotEmpty ? '$name (Caretaker)' : _caretakerName;
            _caretakerPhone = phone.isNotEmpty ? phone : _caretakerPhone;
            if (timing.isNotEmpty) {
              _caretakerTitle = timing;
            }
          }
        }
      }
    } catch (_) {
      // Graceful fallback to default numbers if offline
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _triggerEntranceAnimation();
      }
    }
  }

  Future<void> _makePhoneCall(BuildContext context, String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch dialer for $phone')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dialer error: $e')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String waNumber) async {
    final cleanWa = waNumber.replaceAll(RegExp(r'\D'), '');
    final Uri waUri = Uri.parse('https://wa.me/$cleanWa');
    try {
      if (await canLaunchUrl(waUri)) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp for $waNumber')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WhatsApp error: $e')),
      );
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
    return 'M';
  }

  String _formatPhoneDisplay(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.startsWith('+') ? trimmed : '+91 $trimmed';
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (GoRouter.maybeOf(context) != null) {
      context.go('/menu');
    }
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
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final surfaceBg =
        isDark ? HomeThemeTokens.darkSurface : const Color(0xFFF1F5F4);
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);

    final waSurfaceBg =
        isDark ? const Color(0xFF1E4838) : const Color(0xFFE4F5EC);
    final waIconCol =
        isDark ? const Color(0xFF3DD598) : const Color(0xFF0F7A4F);
    final waCtaBg =
        isDark ? const Color(0xFF3DD598) : const Color(0xFF0F7A4F);
    final waSubtitleCol =
        isDark ? const Color(0xFFA7DEC5) : textSec;
    final dividerCol =
        isDark ? HomeThemeTokens.darkBorder : const Color(0xFFEDF2F1);

    final formattedManagerPhone = _formatPhoneDisplay(_managerPhone);
    final formattedCaretakerPhone = _formatPhoneDisplay(_caretakerPhone);

    final cardShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x20000000) : const Color(0x0A0E1A1F),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ];

    final heroShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x36000000) : const Color(0x220B2231),
        blurRadius: 16,
        offset: const Offset(0, 5),
      ),
    ];

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
                          'Call Management',
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
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: borderCol, width: 1),
                          boxShadow: cardShadow,
                        ),
                        child: _InteractivePress(
                          child: IconButton(
                            icon: Icon(
                              Icons.refresh_rounded,
                              size: 19,
                              color: textPri,
                            ),
                            tooltip: 'Refresh',
                            padding: EdgeInsets.zero,
                            onPressed: _loadPropertyContacts,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ----------------------------------------------------------------
            // 2. MAIN CONTENT
            // ----------------------------------------------------------------
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: tealCol),
                    )
                  : RefreshIndicator(
                      color: tealCol,
                      onRefresh: _loadPropertyContacts,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // --------------------------------------------
                                // DIRECT PROPERTY SUPPORT HERO BANNER
                                // --------------------------------------------
                                _staggeredEntrance(
                                  begin: 0.04,
                                  end: 0.42,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient:
                                          HomeThemeTokens.heroGradient(context),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.08),
                                        width: 1,
                                      ),
                                      boxShadow: heroShadow,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(21),
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: CustomPaint(
                                                painter: _HeroDotGridPainter(),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(18),
                                            child: Row(
                                              children: [
                                                AnimatedBuilder(
                                                  animation: _entranceController,
                                                  builder: (context, iconChild) {
                                                    final disableAnim =
                                                        MediaQuery.maybeDisableAnimationsOf(
                                                              context,
                                                            ) ??
                                                            false;
                                                    final t = disableAnim
                                                        ? 1.0
                                                        : CurvedAnimation(
                                                            parent:
                                                                _entranceController,
                                                            curve: const Interval(
                                                              0.08,
                                                              0.72,
                                                              curve: Curves
                                                                  .easeOutCubic,
                                                            ),
                                                          ).value;
                                                    final ringScale =
                                                        0.88 + (0.12 * t);
                                                    final ringAlpha =
                                                        0.36 - (0.14 * t);
                                                    return SizedBox(
                                                      width: 58,
                                                      height: 58,
                                                      child: Stack(
                                                        alignment:
                                                            Alignment.center,
                                                        children: [
                                                          Transform.scale(
                                                            scale: ringScale,
                                                            child: Container(
                                                              width: 58,
                                                              height: 58,
                                                              decoration:
                                                                  BoxDecoration(
                                                                shape: BoxShape
                                                                    .circle,
                                                                border:
                                                                    Border.all(
                                                                  color: const Color(
                                                                    0xFF8BE3D4,
                                                                  ).withValues(
                                                                    alpha:
                                                                        ringAlpha,
                                                                  ),
                                                                  width: 1.5,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          iconChild!,
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    width: 46,
                                                    height: 46,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                        alpha: 0.14,
                                                      ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.headphones_rounded,
                                                      color: Color(0xFF8BE3D4),
                                                      size: 21,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 13),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Direct property support',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          fontSize: 15.5,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Colors.white,
                                                          letterSpacing: -0.2,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        'Connect instantly with the property manager and on-site staff via phone call or WhatsApp.',
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: const Color(
                                                            0xFFB7C6D2,
                                                          ),
                                                          height: 1.4,
                                                        ),
                                                      ),
                                                    ],
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
                                const SizedBox(height: 22),

                                // --------------------------------------------
                                // 1. PRIMARY PG OWNER / MANAGER SECTION
                                // --------------------------------------------
                                _staggeredEntrance(
                                  begin: 0.16,
                                  end: 0.56,
                                  child: _buildSectionHeading(
                                    title: 'Property Owner',
                                    tealCol: tealCol,
                                    textSec: textSec,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                _staggeredEntrance(
                                  begin: 0.22,
                                  end: 0.70,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: borderCol,
                                        width: 1,
                                      ),
                                      boxShadow: cardShadow,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF2B5A72)
                                                    : HomeThemeTokens.lightNavy,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  _getInitials(_managerName),
                                                  style:
                                                      HomeThemeTokens.manrope(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _managerName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style:
                                                        HomeThemeTokens.manrope(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: textPri,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _managerTitle,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style:
                                                        HomeThemeTokens.manrope(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: textSec,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Divider(height: 1, color: dividerCol),
                                        const SizedBox(height: 12),

                                        // Phone Number Tile with Dialer Action
                                        _InteractivePress(
                                          child: Material(
                                            color: surfaceBg,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: InkWell(
                                              onTap: () => _makePhoneCall(
                                                context,
                                                _managerPhone,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color: cardBg,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      child: Icon(
                                                        Icons.phone_outlined,
                                                        color: tealCol,
                                                        size: 19,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'Manager phone · tap to call',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              color: textSec,
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            formattedManagerPhone,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 15,
                                                              letterSpacing:
                                                                  -0.2,
                                                              color: textPri,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 14,
                                                        vertical: 9,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: tealCol,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.call_rounded,
                                                            size: 14.5,
                                                            color: isDark
                                                                ? const Color(
                                                                    0xFF04201C,
                                                                  )
                                                                : Colors.white,
                                                          ),
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Text(
                                                            'Call',
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              color: isDark
                                                                  ? const Color(
                                                                      0xFF04201C,
                                                                    )
                                                                  : Colors
                                                                      .white,
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
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
                                        ),
                                        const SizedBox(height: 10),

                                        // WhatsApp Tile with Launcher Action
                                        _InteractivePress(
                                          child: Material(
                                            color: waSurfaceBg,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: InkWell(
                                              onTap: () => _openWhatsApp(
                                                context,
                                                _managerWhatsApp,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color: cardBg,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .chat_bubble_outline_rounded,
                                                        color: waIconCol,
                                                        size: 19,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'WhatsApp desk · tap to chat',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              color:
                                                                  waSubtitleCol,
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            formattedManagerPhone,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 15,
                                                              letterSpacing:
                                                                  -0.2,
                                                              color: textPri,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 14,
                                                        vertical: 9,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: waCtaBg,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.send_rounded,
                                                            size: 14,
                                                            color: isDark
                                                                ? const Color(
                                                                    0xFF04201C,
                                                                  )
                                                                : Colors.white,
                                                          ),
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Text(
                                                            'Chat',
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              color: isDark
                                                                  ? const Color(
                                                                      0xFF04201C,
                                                                    )
                                                                  : Colors
                                                                      .white,
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
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
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // --------------------------------------------
                                // 2. NIGHT CARETAKER / SECURITY DESK SECTION
                                // --------------------------------------------
                                _staggeredEntrance(
                                  begin: 0.34,
                                  end: 0.78,
                                  child: _buildSectionHeading(
                                    title: 'Night Caretaker & Security',
                                    tealCol: tealCol,
                                    textSec: textSec,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                _staggeredEntrance(
                                  begin: 0.42,
                                  end: 0.90,
                                  child: _InteractivePress(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: borderCol,
                                          width: 1,
                                        ),
                                        boxShadow: cardShadow,
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(19),
                                        child: InkWell(
                                          onTap: () => _makePhoneCall(
                                            context,
                                            _caretakerPhone,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(19),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: HomeThemeTokens
                                                        .warningBg(context),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      12,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.verified_user_outlined,
                                                    color:
                                                        HomeThemeTokens.warning(
                                                      context,
                                                    ),
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        _caretakerName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 14.5,
                                                          color: textPri,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '$formattedCaretakerPhone · $_caretakerTitle',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: textSec,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Container(
                                                  width: 42,
                                                  height: 42,
                                                  decoration: BoxDecoration(
                                                    color: softTealCol,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: IconButton(
                                                    onPressed: () =>
                                                        _makePhoneCall(
                                                      context,
                                                      _caretakerPhone,
                                                    ),
                                                    icon: Icon(
                                                      Icons.phone_outlined,
                                                      color: tealCol,
                                                      size: 19,
                                                    ),
                                                    tooltip: 'Call Caretaker',
                                                    padding: EdgeInsets.zero,
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
}

/// Subtle architectural dot-grid backdrop inside the navy support banner.
class _HeroDotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const step = 14.0;
    for (double y = 7; y < size.height; y += step) {
      for (double x = 7; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
