import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen>
    with TickerProviderStateMixin {
  late final List<Map<String, dynamic>> _notices;
  late final AnimationController _entranceController;
  late final AnimationController _dotController;
  bool _animationStarted = false;
  bool _isRefreshing = false;
  String? _apiErrorMessage;

  static const List<String> _monthShortNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _notices = [
      {
        'id': 'NOTIF-1',
        'title': 'Water supply maintenance',
        'description':
            'Water will be off tomorrow from 10:00 AM to 2:00 PM for solar pipeline servicing.',
        'category': 'Facility',
        'date': 'Today, 10:00 AM',
        'icon': Icons.water_drop_rounded,
        'isImportant': true,
      },
      {
        'id': 'NOTIF-3',
        'title': 'High-Speed Wi-Fi Upgrade',
        'description':
            'Mesh router firmware across Floor 1 and Floor 2 has been upgraded to 300 Mbps bandwidth.',
        'category': 'Internet',
        'date': '24 Oct 2026',
        'icon': Icons.wifi_rounded,
        'isImportant': false,
      },
      {
        'id': 'NOTIF-4',
        'title': 'Visitor Timing Reminder',
        'description':
            'Visitors and guests are allowed in the common lounge area until 9:00 PM daily.',
        'category': 'Rules',
        'date': '20 Oct 2026',
        'icon': Icons.schedule_rounded,
        'isImportant': false,
      },
      {
        'id': 'NOTIF-5',
        'title': 'Scheduled Pest Control Drive',
        'description':
            'Bi-monthly pest control and deep cleaning will be conducted this Sunday from 11:00 AM.',
        'category': 'Maintenance',
        'date': '18 Oct 2026',
        'icon': Icons.cleaning_services_rounded,
        'isImportant': false,
      },
    ];
    _loadNoticesFromApi();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _entranceController.value = 1.0;
        _dotController.value = 1.0;
      } else {
        _entranceController.forward();
        _dotController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  Future<void> _loadNoticesFromApi({bool userInitiated = false}) async {
    if (userInitiated && mounted) {
      setState(() {
        _isRefreshing = true;
        _apiErrorMessage = null;
      });
    }
    try {
      final list = await ResidentApiService.getNotices();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _notices.clear();
          _apiErrorMessage = null;
          for (final n in list) {
            final rawCategory = (n['category'] ?? 'Notice').toString().trim();
            final rawCreatedAt = n['created_at']?.toString() ?? '';
            final bool isImportant = n['priority'] == 'HIGH' ||
                n['priority'] == 'URGENT' ||
                n['is_pinned'] == true;

            _notices.add({
              'id': n['id']?.toString() ?? '',
              'title': (n['title'] ?? 'Notice').toString(),
              'description': (n['message'] ?? n['content'] ?? '').toString(),
              'category': rawCategory.isNotEmpty ? rawCategory : 'Notice',
              'date': _formatNoticeDate(rawCreatedAt),
              'icon': _resolveNoticeIcon(
                rawCategory,
                (n['title'] ?? '').toString(),
              ),
              'isImportant': isImportant,
            });
          }
        });
      }
    } catch (e) {
      debugPrint('API getNotices error: $e');
      if (userInitiated && mounted) {
        setState(() {
          _apiErrorMessage = 'Could not refresh notices right now.';
        });
      }
    } finally {
      if (mounted && _isRefreshing) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String _formatNoticeDate(String rawDate) {
    if (rawDate.trim().isEmpty) return 'Recent';
    final parsed = DateTime.tryParse(rawDate.trim());
    if (parsed == null) {
      return rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    }
    final local = parsed.toLocal();
    final now = DateTime.now();
    final isSameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isSameDay) {
      final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      final amPm = local.hour >= 12 ? 'PM' : 'AM';
      return 'Today, ${hour12.toString().padLeft(2, '0')}:$minute $amPm';
    }
    final day = local.day.toString().padLeft(2, '0');
    final mon = _monthShortNames[local.month - 1];
    return '$day $mon ${local.year}';
  }

  IconData _resolveNoticeIcon(String category, String title) {
    final c = '$category $title'.toLowerCase();
    if (c.contains('water') || c.contains('facility')) {
      return Icons.water_drop_rounded;
    }
    if (c.contains('wifi') || c.contains('wi-fi') || c.contains('internet')) {
      return Icons.wifi_rounded;
    }
    if (c.contains('rule') || c.contains('visitor') || c.contains('timing')) {
      return Icons.apartment_rounded;
    }
    if (c.contains('maint') || c.contains('clean') || c.contains('pest')) {
      return Icons.cleaning_services_rounded;
    }
    if (c.contains('finance') || c.contains('rent') || c.contains('invoice')) {
      return Icons.credit_card_outlined;
    }
    return Icons.campaign_outlined;
  }

  bool _isTodayNotice(Map<String, dynamic> notice) {
    final dateStr = (notice['date'] ?? '').toString().toLowerCase().trim();
    return dateStr.startsWith('today');
  }

  String _formatDisplayTimeOrDate(String rawDate) {
    final clean = rawDate.trim();
    if (clean.toLowerCase().startsWith('today,')) {
      return clean.substring(6).trim();
    }
    return clean;
  }

  Widget _staggeredHeader({required Widget child}) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, inner) {
        final t = anim.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -10 * (1 - t)),
            child: inner,
          ),
        );
      },
    );
  }

  Widget _staggeredItem({
    required double begin,
    required double end,
    required Widget child,
  }) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        begin.clamp(0.0, 0.95),
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

  void _restoreSampleNotices() {
    setState(() {
      _notices.addAll([
        {
          'id': 'NOTIF-1',
          'title': 'Water supply maintenance',
          'description':
              'Water will be off tomorrow from 10:00 AM to 2:00 PM.',
          'category': 'Facility',
          'date': 'Today, 10:00 AM',
          'icon': Icons.water_drop_rounded,
          'isImportant': true,
        },
        {
          'id': 'NOTIF-3',
          'title': 'High-Speed Wi-Fi Upgrade',
          'description': 'Mesh router bandwidth upgraded to 300 Mbps.',
          'category': 'Internet',
          'date': '24 Oct 2026',
          'icon': Icons.wifi_rounded,
          'isImportant': false,
        },
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);

    final todayNotices = _notices.where(_isTodayNotice).toList();
    final earlierNotices =
        _notices.where((n) => !_isTodayNotice(n)).toList();

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --------------------------------------------------------------
                // A. HEADER BAR
                // --------------------------------------------------------------
                _staggeredHeader(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        _ScalePress(
                          onTap: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/home');
                            }
                          },
                          child: Semantics(
                            button: true,
                            label: 'Back',
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: isDark
                                      ? borderCol
                                      : const Color(0xFFE8EDEC),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.10)
                                        : const Color(0x060E1A1F),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                size: 20,
                                color: textPri,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Notices & Circulars',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HomeThemeTokens.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: textPri,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_notices.isNotEmpty)
                          Tooltip(
                            message: 'Clear for Empty State Preview',
                            child: _ScalePress(
                              onTap: () {
                                setState(() => _notices.clear());
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Notices cleared to preview Empty State with Lottie animation',
                                    ),
                                  ),
                                );
                              },
                              child: Semantics(
                                button: true,
                                label: 'Clear for Empty State Preview',
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(13),
                                    border: Border.all(
                                      color: isDark
                                          ? borderCol
                                          : const Color(0xFFE8EDEC),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 19,
                                    color: textSec,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 42),
                      ],
                    ),
                  ),
                ),

                if (_isRefreshing)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: tealCol,
                    backgroundColor: HomeThemeTokens.softTeal(context),
                  ),

                // --------------------------------------------------------------
                // B. BODY (EMPTY STATE OR GROUPED NOTICES LIST)
                // --------------------------------------------------------------
                Expanded(
                  child: RefreshIndicator(
                    color: tealCol,
                    backgroundColor: cardBg,
                    onRefresh: () => _loadNoticesFromApi(userInitiated: true),
                    child: _notices.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 20,
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: (constraints.maxHeight - 40)
                                        .clamp(0.0, double.infinity),
                                  ),
                                  child: Center(
                                    child: _staggeredItem(
                                      begin: 0.1,
                                      end: 0.6,
                                      child: _buildEmptyState(
                                        context: context,
                                        isDark: isDark,
                                        cardBg: cardBg,
                                        borderCol: borderCol,
                                        textPri: textPri,
                                        textSec: textSec,
                                        tealCol: tealCol,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_apiErrorMessage != null)
                                  _buildErrorBanner(
                                    context: context,
                                    tealCol: tealCol,
                                  ),
                                if (todayNotices.isNotEmpty) ...[
                                  _staggeredItem(
                                    begin: 0.08,
                                    end: 0.44,
                                    child: _buildGroupHeader(
                                      label: 'Today',
                                      textSec: textSec,
                                      borderCol: borderCol,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...todayNotices.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final double begin =
                                        (0.14 + idx * 0.08).clamp(0.14, 0.72);
                                    final double end =
                                        (begin + 0.36).clamp(0.40, 1.0);
                                    return _staggeredItem(
                                      begin: begin,
                                      end: end,
                                      child: _buildNoticeCard(
                                        context: context,
                                        item: entry.value,
                                        isDark: isDark,
                                        cardBg: cardBg,
                                        borderCol: borderCol,
                                        textPri: textPri,
                                        textSec: textSec,
                                      ),
                                    );
                                  }),
                                  if (earlierNotices.isNotEmpty)
                                    const SizedBox(height: 6),
                                ],
                                if (earlierNotices.isNotEmpty) ...[
                                  _staggeredItem(
                                    begin: todayNotices.isNotEmpty ? 0.24 : 0.10,
                                    end: todayNotices.isNotEmpty ? 0.62 : 0.46,
                                    child: _buildGroupHeader(
                                      label: todayNotices.isNotEmpty
                                          ? 'Earlier'
                                          : 'All Notices',
                                      textSec: textSec,
                                      borderCol: borderCol,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...earlierNotices
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                    final idx =
                                        entry.key + todayNotices.length;
                                    final double begin =
                                        (0.24 + idx * 0.08).clamp(0.20, 0.75);
                                    final double end =
                                        (begin + 0.34).clamp(0.45, 1.0);
                                    return _staggeredItem(
                                      begin: begin,
                                      end: end,
                                      child: _buildNoticeCard(
                                        context: context,
                                        item: entry.value,
                                        isDark: isDark,
                                        cardBg: cardBg,
                                        borderCol: borderCol,
                                        textPri: textPri,
                                        textSec: textSec,
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner({
    required BuildContext context,
    required Color tealCol,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HomeThemeTokens.warningBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HomeThemeTokens.warning(context).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: HomeThemeTokens.warning(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _apiErrorMessage!,
              style: HomeThemeTokens.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HomeThemeTokens.warning(context),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _loadNoticesFromApi(userInitiated: true),
            child: Text(
              'Retry',
              style: HomeThemeTokens.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tealCol,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader({
    required String label,
    required Color textSec,
    required Color borderCol,
  }) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: HomeThemeTokens.manrope(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: textSec,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: borderCol),
        ),
      ],
    );
  }

  ({Color iconBg, Color iconFg, Color chipBg, Color chipFg})
      _resolveCategoryPalette({
    required BuildContext context,
    required String category,
    required bool isDark,
    required Color textPri,
  }) {
    final c = category.toLowerCase();
    if (c.contains('facility') || c.contains('water')) {
      return (
        iconBg: HomeThemeTokens.foodBg(context),
        iconFg: HomeThemeTokens.foodIcon(context),
        chipBg: HomeThemeTokens.foodBg(context),
        chipFg: HomeThemeTokens.foodIcon(context),
      );
    }
    if (c.contains('internet') || c.contains('wi-fi') || c.contains('wifi')) {
      return (
        iconBg: isDark ? const Color(0xFF323F49) : const Color(0xFFEEF1F0),
        iconFg: textPri,
        chipBg: HomeThemeTokens.foodBg(context),
        chipFg: HomeThemeTokens.foodIcon(context),
      );
    }
    if (c.contains('rule') || c.contains('important')) {
      return (
        iconBg: HomeThemeTokens.warningBg(context),
        iconFg: HomeThemeTokens.warning(context),
        chipBg: HomeThemeTokens.warningBg(context),
        chipFg: HomeThemeTokens.warning(context),
      );
    }
    return (
      iconBg: HomeThemeTokens.softTeal(context),
      iconFg: HomeThemeTokens.teal(context),
      chipBg: HomeThemeTokens.softTeal(context),
      chipFg: HomeThemeTokens.teal(context),
    );
  }

  Widget _buildNoticeCard({
    required BuildContext context,
    required Map<String, dynamic> item,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
  }) {
    final isImportant = item['isImportant'] == true;
    final category = (item['category'] ?? 'Notice').toString();
    final title = (item['title'] ?? 'Notice').toString();
    final description = (item['description'] ?? '').toString();
    final rawDate = (item['date'] ?? '').toString();
    final dateLabel = _formatDisplayTimeOrDate(rawDate);
    final IconData icon = item['icon'] is IconData
        ? item['icon'] as IconData
        : _resolveNoticeIcon(category, title);

    final palette = _resolveCategoryPalette(
      context: context,
      category: category,
      isDark: isDark,
      textPri: textPri,
    );

    final Color importantBadgeBg =
        isDark ? const Color(0xFF4B2841) : const Color(0xFFFCE7F0);
    final Color importantBadgeFg =
        isDark ? const Color(0xFFF9A8D4) : const Color(0xFF9D174D);

    final Color cardBorderColor = isImportant
        ? (isDark ? const Color(0xFF2F6F68) : const Color(0xFFB9D9D4))
        : (isDark ? borderCol : const Color(0xFFE6ECEA));

    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Color dotColor =
        isDark ? HomeThemeTokens.darkBellDot : HomeThemeTokens.lightBellDot;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ScalePress(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cardBorderColor,
              width: isImportant ? 1.15 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.12)
                    : const Color(0x060E1A1F),
                blurRadius: 6,
                spreadRadius: -1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Icon Box
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.iconBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isDark ? Colors.white : const Color(0xFF0E1A1F))
                        .withValues(alpha: 0.05),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: palette.iconFg,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              // Right Details Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chips + Date/Time Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.chipBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  category,
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: palette.chipFg,
                                  ),
                                ),
                              ),
                              if (isImportant)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: importantBadgeBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Important',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: importantBadgeFg,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isImportant) ...[
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (!disableAnim)
                                      AnimatedBuilder(
                                        animation: _dotController,
                                        builder: (context, _) {
                                          final t = _dotController.value;
                                          final scale = 1.0 + t * 1.4;
                                          final alpha =
                                              ((1.0 - t) * 0.45).clamp(0.0, 1.0);
                                          return Transform.scale(
                                            scale: scale,
                                            child: Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: dotColor.withValues(
                                                  alpha: alpha,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: dotColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              dateLabel,
                              style: HomeThemeTokens.manrope(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: textSec,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: HomeThemeTokens.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                        height: 1.3,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: HomeThemeTokens.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textSec,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required BuildContext context,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required Color tealCol,
  }) {
    final softTealCol = HomeThemeTokens.softTeal(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? borderCol : const Color(0xFFE6ECEA),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: softTealCol,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Lottie.asset(
                'assets/animations/empty_notices.json',
                width: 34,
                height: 34,
                repeat: false,
                animate: !disableAnim,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.notifications_none_rounded,
                  size: 28,
                  color: tealCol,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing Here Yet',
            textAlign: TextAlign.center,
            style: HomeThemeTokens.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: textPri,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No data found for your request.',
            textAlign: TextAlign.center,
            style: HomeThemeTokens.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textSec,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _ScalePress(
            onTap: _restoreSampleNotices,
            child: Semantics(
              button: true,
              label: 'Refresh Notices',
              child: Container(
                constraints: const BoxConstraints(minHeight: 42),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tealCol,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 17,
                      color: isDark ? const Color(0xFF04201C) : Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Refresh Notices',
                      style: HomeThemeTokens.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? const Color(0xFF04201C) : Colors.white,
                      ),
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
}

/// Lightweight tactile press feedback wrapper honoring reduced motion.
class _ScalePress extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _ScalePress({
    required this.child,
    required this.onTap,
  });

  @override
  State<_ScalePress> createState() => _ScalePressState();
}

class _ScalePressState extends State<_ScalePress> {
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
        child: widget.child,
      ),
    );
  }
}
