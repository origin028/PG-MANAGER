import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/network/token_storage.dart';
import '../../core/theme/app_theme.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _sheenController;
  bool _animationStarted = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _entranceController.value = 1.0;
        _sheenController.value = 1.0;
      } else {
        _entranceController.forward();
        _sheenController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _sheenController.dispose();
    super.dispose();
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
    final savedProfile = TokenStorage.residentProfile;
    final resident = (savedProfile != null &&
            savedProfile.isNotEmpty &&
            AppData.currentResident['phone'] == AppData.residents.first['phone'] &&
            AppData.currentResident['room_number'] == null)
        ? savedProfile
        : AppData.currentResident;

    final residentInfo =
        (resident['resident_info'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final stayDetails =
        (resident['stay_details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final rawName = residentInfo['full_name'] ??
        resident['full_name'] ??
        resident['name'] ??
        'Resident';
    final name = rawName.toString().trim().isNotEmpty
        ? rawName.toString().trim()
        : 'Resident';

    final rawRoom = stayDetails['room_number'] ??
        resident['room_number'] ??
        resident['room'];
    final room = (rawRoom != null && rawRoom.toString().trim().isNotEmpty)
        ? rawRoom.toString().trim()
        : null;

    final rawPhone = (residentInfo['phone'] ??
            resident['phone'] ??
            '9876543210')
        .toString()
        .trim();
    final formattedPhone =
        rawPhone.startsWith('+') ? rawPhone : '+91 $rawPhone';

    final String subtitleMeta =
        room != null ? 'Room $room · $formattedPhone' : formattedPhone;

    final bool isRentPaid =
        resident['rent_status']?.toString().toLowerCase() == 'paid';

    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final avatarPop = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.86, end: 1.04), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.0), weight: 40),
    ]).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.06, 0.56, curve: Curves.easeOutCubic),
      ),
    );

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ------------------------------------------------------------
                  // 1. NAVY RESIDENT PROFILE HERO CARD
                  // ------------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.06,
                    end: 0.44,
                    child: _InteractivePress(
                      onTap: () => context.push('/profile'),
                      builder: (context, isPressed) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: HomeThemeTokens.heroGradient(context),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? const Color(0x400B2231)
                                    : const Color(0x280B2231),
                                blurRadius: 16,
                                spreadRadius: -6,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -60,
                                  top: -70,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 180,
                                      height: 180,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            const Color(0xFF42C8B4)
                                                .withValues(alpha: 0.22),
                                            const Color(0xFF42C8B4)
                                                .withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!disableAnim)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: AnimatedBuilder(
                                        animation: _sheenController,
                                        builder: (context, _) {
                                          final v = _sheenController.value;
                                          if (v <= 0.0 || v >= 1.0) {
                                            return const SizedBox.shrink();
                                          }
                                          return FractionalTranslation(
                                            translation:
                                                Offset(-1.2 + v * 2.5, 0),
                                            child: Container(
                                              width: 80,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [
                                                    Colors.white
                                                        .withValues(alpha: 0.0),
                                                    Colors.white.withValues(
                                                        alpha: 0.11),
                                                    Colors.white
                                                        .withValues(alpha: 0.0),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Row(
                                    children: [
                                      ScaleTransition(
                                        scale: disableAnim
                                            ? const AlwaysStoppedAnimation(1.0)
                                            : avatarPop,
                                        child: Container(
                                          width: 56,
                                          height: 56,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              _getInitials(name),
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 18.5,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    HomeThemeTokens.lightNavy,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
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
                                                fontSize: 17.5,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              subtitleMeta,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFFB7C6D2),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AnimatedSlide(
                                        offset: (!disableAnim && isPressed)
                                            ? const Offset(0.15, 0)
                                            : Offset.zero,
                                        duration:
                                            const Duration(milliseconds: 140),
                                        child: const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                          color: Color(0xFFB7C6D2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ------------------------------------------------------------
                  // 3. SERVICES & MANAGEMENT
                  // ------------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.14,
                    end: 0.52,
                    child: _buildSectionHeading(
                      label: 'SERVICES & MANAGEMENT',
                      tealCol: tealCol,
                      textSec: textSec,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _staggeredEntrance(
                    begin: 0.18,
                    end: 0.58,
                    child: _buildSectionCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      children: [
                        _buildMenuItem(
                          context: context,
                          icon: Icons.credit_card_outlined,
                          iconColor: HomeThemeTokens.success(context),
                          iconBg: HomeThemeTokens.successBg(context),
                          title: 'Rent & Deposit Details',
                          subtitle: 'Invoices, dues & payment receipts',
                          trailingBadge: !isRentPaid ? '1 due' : null,
                          onTap: () => context.push('/rent-deposit'),
                        ),
                        _buildInsetDivider(borderCol),
                        _buildMenuItem(
                          context: context,
                          icon: Icons.apartment_rounded,
                          iconColor: HomeThemeTokens.foodIcon(context),
                          iconBg: HomeThemeTokens.foodBg(context),
                          title: 'Property Details',
                          subtitle: 'Address, room, floor & house rules',
                          onTap: () => context.push('/property-details'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ------------------------------------------------------------
                  // 4. HELP & SUPPORT
                  // ------------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.26,
                    end: 0.66,
                    child: _buildSectionHeading(
                      label: 'HELP & SUPPORT',
                      tealCol: tealCol,
                      textSec: textSec,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _staggeredEntrance(
                    begin: 0.30,
                    end: 0.72,
                    child: _buildSectionCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      children: [
                        _buildMenuItem(
                          context: context,
                          icon: Icons.warning_amber_rounded,
                          iconColor: HomeThemeTokens.warning(context),
                          iconBg: HomeThemeTokens.warningBg(context),
                          title: 'Raise Complaint',
                          subtitle: 'Report maintenance, Wi-Fi or room issues',
                          onTap: () => context.push('/raise-complaint'),
                        ),
                        _buildInsetDivider(borderCol),
                        _buildMenuItem(
                          context: context,
                          icon: Icons.headset_mic_outlined,
                          iconColor: HomeThemeTokens.success(context),
                          iconBg: HomeThemeTokens.successBg(context),
                          title: 'Call Management',
                          subtitle: 'Contact PG manager & WhatsApp desk',
                          onTap: () => context.push('/call-management'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ------------------------------------------------------------
                  // 5. ACCOUNT SETTINGS
                  // ------------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.38,
                    end: 0.80,
                    child: _buildSectionHeading(
                      label: 'ACCOUNT SETTINGS',
                      tealCol: tealCol,
                      textSec: textSec,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _staggeredEntrance(
                    begin: 0.42,
                    end: 0.86,
                    child: _buildSectionCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderCol: borderCol,
                      children: [
                        _buildMenuItem(
                          context: context,
                          icon: Icons.settings_outlined,
                          iconColor: textPri,
                          iconBg: isDark
                              ? const Color(0xFF323F49)
                              : const Color(0xFFEEF1F0),
                          title: 'Settings',
                          subtitle: 'Theme, language & account logout',
                          onTap: () => context.push('/settings'),
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
    );
  }

  Widget _buildSectionHeading({
    required String label,
    required Color tealCol,
    required Color textSec,
  }) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: tealCol,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeThemeTokens.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: textSec,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? borderCol : const Color(0xFFE8EDEC),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.12)
                : const Color(0x060E1A1F),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildInsetDivider(Color borderCol) {
    return Container(
      margin: const EdgeInsets.only(left: 70),
      height: 1,
      color: borderCol,
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? trailingBadge,
    required VoidCallback onTap,
  }) {
    final isDark = HomeThemeTokens.isDark(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return _InteractivePress(
      onTap: onTap,
      builder: (context, isPressed) {
        return Container(
          color: isPressed
              ? (isDark
                  ? HomeThemeTokens.darkSurface.withValues(alpha: 0.55)
                  : const Color(0xFFF6F9F8))
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isDark ? Colors.white : const Color(0xFF0E1A1F))
                        .withValues(alpha: 0.05),
                    width: 1,
                  ),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingBadge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: HomeThemeTokens.warningBg(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trailingBadge,
                    style: HomeThemeTokens.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HomeThemeTokens.warning(context),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              AnimatedSlide(
                offset: (!disableAnim && isPressed)
                    ? const Offset(0.18, 0)
                    : Offset.zero,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: textSec,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Press feedback wrapper honoring reduced motion with subtle scale and state flag.
class _InteractivePress extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool isPressed) builder;

  const _InteractivePress({
    required this.onTap,
    required this.builder,
  });

  @override
  State<_InteractivePress> createState() => _InteractivePressState();
}

class _InteractivePressState extends State<_InteractivePress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: (_pressed && !disableAnim) ? 0.985 : 1.0,
        duration:
            disableAnim ? Duration.zero : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.builder(context, _pressed),
      ),
    );
  }
}
