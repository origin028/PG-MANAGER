import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class FoodMenuScreen extends StatefulWidget {
  const FoodMenuScreen({super.key});

  @override
  State<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends State<FoodMenuScreen>
    with TickerProviderStateMixin {
  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  late String _currentDayName;
  late final AnimationController _entranceController;
  late final AnimationController _dotController;
  bool _animationStarted = false;
  bool _isRefreshing = false;
  String? _apiErrorMessage;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _currentDayName = _getTodayDayName();
    AppData.loadResidentsFromStorage().then((_) {
      if (mounted) setState(() {});
    });
    _loadFoodMenuFromApi();
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

  Future<void> _loadFoodMenuFromApi({bool userInitiated = false}) async {
    if (userInitiated && mounted) {
      setState(() {
        _isRefreshing = true;
        _apiErrorMessage = null;
      });
    }
    try {
      final menu = await ResidentApiService.getWeeklyFoodMenu();
      if (menu.isNotEmpty && mounted) {
        final menuByDay = menu['menu_by_day'] as Map?;
        final days = (menu['days'] as List?) ?? [];

        if (menuByDay != null && menuByDay.isNotEmpty) {
          final parsed = <Map<String, dynamic>>[];
          for (final day in _daysOfWeek) {
            final rawItems =
                (menuByDay[day.toUpperCase()] ?? menuByDay[day]) as List?;
            if (rawItems != null && rawItems.isNotEmpty) {
              String breakfast = '';
              String lunch = '';
              String dinner = '';
              String breakfastTime = '7:30–9:30 AM';
              String lunchTime = '12:30–2:30 PM';
              String dinnerTime = '8:00–10:00 PM';

              for (final raw in rawItems) {
                if (raw is! Map) continue;
                final mealType =
                    (raw['meal_type'] ?? '').toString().toUpperCase();
                final dishesList = (raw['dishes'] as List?)
                        ?.map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList() ??
                    <String>[];
                final dishesText = dishesList.join(', ');
                final start = (raw['start_time'] ?? '').toString().trim();
                final end = (raw['end_time'] ?? '').toString().trim();
                final timing = (start.isNotEmpty && end.isNotEmpty)
                    ? '$start–$end'
                    : (start.isNotEmpty ? start : '');

                if (mealType == 'BREAKFAST') {
                  if (dishesText.isNotEmpty) breakfast = dishesText;
                  if (timing.isNotEmpty) breakfastTime = timing;
                } else if (mealType == 'LUNCH') {
                  if (dishesText.isNotEmpty) lunch = dishesText;
                  if (timing.isNotEmpty) lunchTime = timing;
                } else if (mealType == 'DINNER') {
                  if (dishesText.isNotEmpty) dinner = dishesText;
                  if (timing.isNotEmpty) dinnerTime = timing;
                }
              }

              if (breakfast.isNotEmpty || lunch.isNotEmpty || dinner.isNotEmpty) {
                parsed.add({
                  'day': day,
                  'breakfast': breakfast.isNotEmpty ? breakfast : 'Not specified',
                  'lunch': lunch.isNotEmpty ? lunch : 'Not specified',
                  'dinner': dinner.isNotEmpty ? dinner : 'Not specified',
                  'breakfast_time': breakfastTime,
                  'lunch_time': lunchTime,
                  'dinner_time': dinnerTime,
                });
              }
            }
          }
          if (parsed.isNotEmpty) {
            setState(() {
              AppData.foodMenu = parsed;
              _apiErrorMessage = null;
            });
          }
        } else if (days.isNotEmpty) {
          setState(() {
            AppData.foodMenu = days
                .map((d) => <String, dynamic>{
                      'day': d['day_of_week'] ?? 'Monday',
                      'breakfast': d['breakfast'] ?? '',
                      'lunch': d['lunch'] ?? '',
                      'dinner': d['dinner'] ?? '',
                    })
                .toList();
            _apiErrorMessage = null;
          });
        }
      }
    } catch (e) {
      debugPrint('API getWeeklyFoodMenu error: $e');
      if (userInitiated && mounted) {
        setState(() {
          _apiErrorMessage = 'Could not refresh weekly food menu.';
        });
      }
    } finally {
      if (mounted && _isRefreshing) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String _getTodayDayName() {
    final weekday = DateTime.now().weekday; // 1 = Monday, 7 = Sunday
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

  String _getNextMealType() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'Breakfast';
    if (hour < 15) return 'Lunch';
    return 'Dinner';
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
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final nextMeal = _getNextMealType();

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              onRefresh: () async {
                await AppData.loadResidentsFromStorage();
                await _loadFoodMenuFromApi(userInitiated: true);
                if (mounted) setState(() {});
              },
              color: tealCol,
              backgroundColor: cardBg,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Header + Status Pills matching HTML reference
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: _staggeredEntrance(
                        begin: 0.0,
                        end: 0.36,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fresh, hygienic meals cooked daily',
                              style: HomeThemeTokens.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textSec,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Weekly Food Menu',
                              style: HomeThemeTokens.manrope(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: textPri,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: HomeThemeTokens.foodBg(context),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Today: $_currentDayName',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: HomeThemeTokens.foodIcon(context),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: softTealCol,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '3 meals a day',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: tealCol,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            AnimatedSwitcher(
                              duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              child: _isRefreshing
                                  ? Padding(
                                      key: const ValueKey('food_refreshing'),
                                      padding: const EdgeInsets.only(top: 12),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          minHeight: 2.5,
                                          color: tealCol,
                                          backgroundColor: softTealCol,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('food_idle'),
                                    ),
                            ),
                            if (_apiErrorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: HomeThemeTokens.warningBg(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: HomeThemeTokens.warning(context)
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 15,
                                      color: HomeThemeTokens.warning(context),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _apiErrorMessage!,
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              HomeThemeTokens.warning(context),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _loadFoodMenuFromApi(
                                        userInitiated: true,
                                      ),
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
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Weekly Day Cards List
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final day = _daysOfWeek[index];
                          final isToday =
                              day.toLowerCase() == _currentDayName.toLowerCase();
                          final dayData = AppData.foodMenu.firstWhere(
                            (m) =>
                                m['day']?.toString().toLowerCase() ==
                                day.toLowerCase(),
                            orElse: () => {
                              'day': day,
                              'breakfast': 'Poha & Tea',
                              'lunch': 'Dal, Rice, Roti, Sabzi',
                              'dinner': 'Paneer, Roti, Rice',
                            },
                          );

                          final double start =
                              (0.08 + index * 0.07).clamp(0.08, 0.65);
                          final double finish =
                              (start + 0.32).clamp(0.35, 1.0);

                          return _staggeredEntrance(
                            begin: start,
                            end: finish,
                            child: _buildDayCard(
                              data: dayData,
                              isToday: isToday,
                              nextMeal: nextMeal,
                              isDark: isDark,
                              cardBg: cardBg,
                              borderCol: borderCol,
                              textPri: textPri,
                              textSec: textSec,
                              context: context,
                            ),
                          );
                        },
                        childCount: _daysOfWeek.length,
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

  Widget _buildDayCard({
    required Map<String, dynamic> data,
    required bool isToday,
    required String nextMeal,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required BuildContext context,
  }) {
    final day = data['day']?.toString() ?? 'Monday';
    final breakfast = data['breakfast']?.toString() ?? 'Not specified';
    final lunch = data['lunch']?.toString() ?? 'Not specified';
    final dinner = data['dinner']?.toString() ?? 'Not specified';

    final breakfastTime =
        (data['breakfast_time'] ?? '7:30–9:30 AM').toString();
    final lunchTime = (data['lunch_time'] ?? '12:30–2:30 PM').toString();
    final dinnerTime = (data['dinner_time'] ?? '8:00–10:00 PM').toString();

    final Color cardBorder = isToday
        ? (isDark ? const Color(0xFF2F6F68) : const Color(0xFF9CCBC4))
        : (isDark ? borderCol : const Color(0xFFE8EDEC));

    final Color normalHeaderBg =
        isDark ? HomeThemeTokens.darkSurface : const Color(0xFFF6F9F8);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cardBorder,
          width: isToday ? 1.2 : 1.0,
        ),
        boxShadow: [
          if (isToday)
            BoxShadow(
              color: const Color(0xFF0B6B63)
                  .withValues(alpha: isDark ? 0.12 : 0.06),
              blurRadius: 10,
              spreadRadius: -3,
              offset: const Offset(0, 3),
            )
          else
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.10)
                  : const Color(0x050E1A1F),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Day Card Header Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10.5),
              decoration: BoxDecoration(
                color: isToday ? null : normalHeaderBg,
                gradient: isToday
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? const [Color(0xFF204C60), Color(0xFF2D6279)]
                            : const [Color(0xFF0B2231), Color(0xFF12394A)],
                      )
                    : null,
                border: Border(
                  bottom: BorderSide(color: borderCol, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      day,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: isToday ? Colors.white : textPri,
                      ),
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Today',
                        style: HomeThemeTokens.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Breakfast Row
            _buildMealRow(
              mealName: 'Breakfast',
              timeSlot: breakfastTime,
              menuText: breakfast,
              icon: Icons.wb_sunny_rounded,
              iconBg: isDark
                  ? HomeThemeTokens.darkWarningBg
                  : HomeThemeTokens.lightWarningBg,
              iconColor: isDark
                  ? HomeThemeTokens.darkWarning
                  : const Color(0xFFB45309),
              isNext: isToday && nextMeal == 'Breakfast',
              isDark: isDark,
              textPri: textPri,
              textSec: textSec,
              context: context,
            ),
            _buildInsetDivider(borderCol),

            // Lunch Row
            _buildMealRow(
              mealName: 'Lunch',
              timeSlot: lunchTime,
              menuText: lunch,
              icon: Icons.lunch_dining_rounded,
              iconBg: HomeThemeTokens.successBg(context),
              iconColor: HomeThemeTokens.success(context),
              isNext: isToday && nextMeal == 'Lunch',
              isDark: isDark,
              textPri: textPri,
              textSec: textSec,
              context: context,
            ),
            _buildInsetDivider(borderCol),

            // Dinner Row
            _buildMealRow(
              mealName: 'Dinner',
              timeSlot: dinnerTime,
              menuText: dinner,
              icon: Icons.nightlight_round_rounded,
              iconBg: HomeThemeTokens.foodBg(context),
              iconColor: HomeThemeTokens.foodIcon(context),
              isNext: isToday && nextMeal == 'Dinner',
              isDark: isDark,
              textPri: textPri,
              textSec: textSec,
              context: context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsetDivider(Color borderCol) {
    return Container(
      margin: const EdgeInsets.only(left: 66),
      height: 1,
      color: borderCol,
    );
  }

  Widget _buildVegSymbol(BuildContext context) {
    final vegColor = HomeThemeTokens.success(context);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: vegColor, width: 1.4),
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: vegColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildMealRow({
    required String mealName,
    required String timeSlot,
    required String menuText,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required bool isNext,
    required bool isDark,
    required Color textPri,
    required Color textSec,
    required BuildContext context,
  }) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final lowerMenu = menuText.toLowerCase();
    final isNonVeg = lowerMenu.contains('egg') ||
        lowerMenu.contains('chicken') ||
        lowerMenu.contains('mutton') ||
        lowerMenu.contains('fish');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: isNext
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isDark
                    ? const [Color(0xFF20474A), Color(0xFF252F37)]
                    : const [Color(0xFFF0F8F6), Color(0xFFFFFFFF)],
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : const Color(0xFF0E1A1F))
                    .withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      mealName,
                      style: HomeThemeTokens.manrope(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: textSec,
                      ),
                    ),
                    Text(
                      ' · $timeSlot',
                      style: HomeThemeTokens.manrope(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: textSec,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2.5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!isNonVeg) ...[
                      _buildVegSymbol(context),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        menuText,
                        style: HomeThemeTokens.manrope(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isNext) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: HomeThemeTokens.successBg(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: HomeThemeTokens.success(context)
                                        .withValues(alpha: alpha),
                                  ),
                                ),
                              );
                            },
                          ),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: HomeThemeTokens.success(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Next',
                    style: HomeThemeTokens.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HomeThemeTokens.success(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
