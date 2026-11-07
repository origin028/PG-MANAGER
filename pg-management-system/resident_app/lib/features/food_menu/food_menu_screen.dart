import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class FoodMenuScreen extends StatefulWidget {
  const FoodMenuScreen({super.key});

  @override
  State<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends State<FoodMenuScreen> {
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

  @override
  void initState() {
    super.initState();
    _currentDayName = _getTodayDayName();
    AppData.loadResidentsFromStorage().then((_) {
      if (mounted) setState(() {});
    });
    _loadFoodMenuFromApi();
  }

  void _loadFoodMenuFromApi() async {
    try {
      final menu = await ResidentApiService.getWeeklyFoodMenu();
      if (menu.isNotEmpty && mounted) {
        final days = (menu['days'] as List?) ?? [];
        if (days.isNotEmpty) {
          setState(() {
            AppData.foodMenu = days.map((d) => <String, dynamic>{
              'day': d['day_of_week'] ?? 'Monday',
              'breakfast': d['breakfast'] ?? '',
              'lunch': d['lunch'] ?? '',
              'dinner': d['dinner'] ?? '',
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('API getWeeklyFoodMenu error: $e');
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

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final pageBg = AppTheme.pageBg(context);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              onRefresh: () async {
                await AppData.loadResidentsFromStorage();
                if (mounted) setState(() {});
              },
              color: AppTheme.primaryBlue,
              child: CustomScrollView(
                slivers: [
                  // App Bar / Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF451A03) : const Color(0xFFFFF7ED),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.restaurant_menu_rounded,
                                        color: Color(0xFFEA580C),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Weekly Food Menu',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: textPri,
                                          letterSpacing: -0.4,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE)),
                                ),
                                child: Text(
                                  'Today: $_currentDayName',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Fresh, hygienic meals cooked daily for all residents.',
                            style: TextStyle(
                              fontSize: 13,
                              color: textSec,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 7 Days List
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final day = _daysOfWeek[index];
                          final isToday = day.toLowerCase() == _currentDayName.toLowerCase();
                          final dayData = AppData.foodMenu.firstWhere(
                            (m) => m['day']?.toString().toLowerCase() == day.toLowerCase(),
                            orElse: () => {
                              'day': day,
                              'breakfast': 'Poha & Tea',
                              'lunch': 'Dal, Rice, Roti, Sabzi',
                              'dinner': 'Paneer, Roti, Rice',
                            },
                          );

                          return _buildDayCard(dayData, isToday, context);
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

  Widget _buildDayCard(Map<String, dynamic> data, bool isToday, BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);

    final day = data['day']?.toString() ?? 'Monday';
    final breakfast = data['breakfast']?.toString() ?? 'Not specified';
    final lunch = data['lunch']?.toString() ?? 'Not specified';
    final dinner = data['dinner']?.toString() ?? 'Not specified';

    final headerBg = isToday
        ? (isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF))
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC));

    final cardBorder = isToday
        ? const Color(0xFF4F46E5)
        : (isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cardBorder,
          width: isToday ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isToday
                ? const Color(0x144F46E5)
                : (isDark ? const Color(0x1A000000) : const Color(0x08000000)),
            blurRadius: isToday ? 14 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day Header Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 15,
                      color: isToday ? const Color(0xFF818CF8) : (isDark ? AppTheme.darkTextSecondary : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      day,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isToday ? (isDark ? Colors.white : const Color(0xFF1E1B4B)) : textPri,
                      ),
                    ),
                  ],
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'TODAY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Breakfast Row
                _buildMealRow(
                  mealName: 'Breakfast',
                  timeSlot: '7:30 AM - 9:30 AM',
                  menuText: breakfast,
                  icon: Icons.wb_sunny_rounded,
                  iconBg: const Color(0xFFFFFBEB),
                  iconColor: const Color(0xFFD97706),
                  isDark: isDark,
                  textPri: textPri,
                  textSec: textSec,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, thickness: 1, color: isDark ? AppTheme.darkBorder : const Color(0xFFF1F5F9)),
                ),

                // Lunch Row
                _buildMealRow(
                  mealName: 'Lunch',
                  timeSlot: '12:30 PM - 2:30 PM',
                  menuText: lunch,
                  icon: Icons.lunch_dining_rounded,
                  iconBg: const Color(0xFFF0FDF4),
                  iconColor: const Color(0xFF059669),
                  isDark: isDark,
                  textPri: textPri,
                  textSec: textSec,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, thickness: 1, color: isDark ? AppTheme.darkBorder : const Color(0xFFF1F5F9)),
                ),

                // Dinner Row
                _buildMealRow(
                  mealName: 'Dinner',
                  timeSlot: '8:00 PM - 10:00 PM',
                  menuText: dinner,
                  icon: Icons.nightlight_round_rounded,
                  iconBg: const Color(0xFFEEF2FF),
                  iconColor: const Color(0xFF4F46E5),
                  isDark: isDark,
                  textPri: textPri,
                  textSec: textSec,
                ),
              ],
            ),
          ),
        ],
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
    required bool isDark,
    required Color textPri,
    required Color textSec,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? iconColor.withValues(alpha: 0.15) : iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      mealName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textSec,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      timeSlot,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                menuText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textPri,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
