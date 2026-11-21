import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/data/app_data.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/widgets/app_dropdown.dart';

class FoodMenuScreen extends StatefulWidget {
  const FoodMenuScreen({super.key});

  @override
  State<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends State<FoodMenuScreen> {
  // Map of controllers for each day: { 'Monday': { 'breakfast': ctrl, 'lunch': ctrl, 'dinner': ctrl } }
  final Map<String, Map<String, TextEditingController>> _controllers = {};
  bool _isSaving = false;

  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  Map<String, String> _mealTimings = {
    'Breakfast': '7:30 AM – 9:00 AM',
    'Lunch': '12:30 PM – 2:00 PM',
    'Dinner': '7:30 PM – 9:00 PM',
  };

  @override
  void initState() {
    super.initState();
    _loadMealTimings();
    _initControllers();
    AppData.selectedPropertyIdNotifier.addListener(_loadMenuFromApi);
    _loadMenuFromApi();
  }

  Future<void> _loadMealTimings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _mealTimings['Breakfast'] = prefs.getString('admin_meal_timing_breakfast') ?? '7:30 AM – 9:00 AM';
        _mealTimings['Lunch'] = prefs.getString('admin_meal_timing_lunch') ?? '12:30 PM – 2:00 PM';
        _mealTimings['Dinner'] = prefs.getString('admin_meal_timing_dinner') ?? '7:30 PM – 9:00 PM';
      });
    } catch (_) {}
  }

  Future<void> _saveMealTimings(Map<String, String> newTimings) async {
    setState(() {
      _mealTimings = Map<String, String>.from(newTimings);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_meal_timing_breakfast', newTimings['Breakfast'] ?? '7:30 AM – 9:00 AM');
      await prefs.setString('admin_meal_timing_lunch', newTimings['Lunch'] ?? '12:30 PM – 2:00 PM');
      await prefs.setString('admin_meal_timing_dinner', newTimings['Dinner'] ?? '7:30 PM – 9:00 PM');
    } catch (_) {}
  }

  void _loadMenuFromApi() async {
    final propId = AppData.selectedPropertyId;
    if (propId == null || propId.isEmpty || propId.startsWith('p')) return;
    try {
      final menuList = await AdminApiService.getWeeklyFoodMenu(propId);
      if (menuList.isNotEmpty && mounted) {
        setState(() {
          for (var item in menuList) {
            final day = item['day_of_week']?.toString().toLowerCase();
            final matchDay = _daysOfWeek.firstWhere(
              (d) => d.toLowerCase() == day,
              orElse: () => '',
            );
            if (matchDay.isNotEmpty && _controllers.containsKey(matchDay)) {
              if (item['breakfast'] != null) _controllers[matchDay]!['breakfast']!.text = item['breakfast'];
              if (item['lunch'] != null) _controllers[matchDay]!['lunch']!.text = item['lunch'];
              if (item['dinner'] != null) _controllers[matchDay]!['dinner']!.text = item['dinner'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('API getWeeklyFoodMenu error: $e');
    }
  }

  void _initControllers() {
    for (var day in _daysOfWeek) {
      final existingDayData = AppData.foodMenu.firstWhere(
        (m) => m['day']?.toString().toLowerCase() == day.toLowerCase(),
        orElse: () => {
          'day': day,
          'breakfast': '',
          'lunch': '',
          'dinner': '',
        },
      );

      _controllers[day] = {
        'breakfast': TextEditingController(text: existingDayData['breakfast']?.toString() ?? ''),
        'lunch': TextEditingController(text: existingDayData['lunch']?.toString() ?? ''),
        'dinner': TextEditingController(text: existingDayData['dinner']?.toString() ?? ''),
      };
    }
  }

  @override
  void dispose() {
    AppData.selectedPropertyIdNotifier.removeListener(_loadMenuFromApi);
    for (var dayControllers in _controllers.values) {
      for (var ctrl in dayControllers.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _saveMenu() async {
    setState(() => _isSaving = true);

    final List<Map<String, dynamic>> updatedMenu = [];
    for (var day in _daysOfWeek) {
      final dayCtrls = _controllers[day]!;
      updatedMenu.add({
        'day': day,
        'breakfast': dayCtrls['breakfast']!.text.trim(),
        'lunch': dayCtrls['lunch']!.text.trim(),
        'dinner': dayCtrls['dinner']!.text.trim(),
      });
    }

    AppData.foodMenu = updatedMenu;
    await AppData.saveFoodMenuToStorage();

    final propId = AppData.selectedPropertyId;
    if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
      try {
        await Future.wait(_daysOfWeek.map((day) {
          final dayCtrls = _controllers[day]!;
          return AdminApiService.saveFoodMenuItem({
            'property_id': propId,
            'day_of_week': day.toUpperCase(),
            'breakfast': dayCtrls['breakfast']!.text.trim(),
            'lunch': dayCtrls['lunch']!.text.trim(),
            'dinner': dayCtrls['dinner']!.text.trim(),
          });
        }));
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save food menu: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Food menu saved successfully!',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showEditTimingsDialog() {
    final breakfastCtrl = TextEditingController(text: _mealTimings['Breakfast']);
    final lunchCtrl = TextEditingController(text: _mealTimings['Lunch']);
    final dinnerCtrl = TextEditingController(text: _mealTimings['Dinner']);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showPremiumDialog(
      context: context,
      builder: (dContext) => PremiumDialog(
        maxWidth: 480,
        title: 'Manage Meal Timings',
        subtitle: 'Configure daily dining hours displayed to residents across all food schedules',
        icon: Icons.schedule_rounded,
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
              _saveMealTimings({
                'Breakfast': breakfastCtrl.text.trim(),
                'Lunch': lunchCtrl.text.trim(),
                'Dinner': dinnerCtrl.text.trim(),
              });
              Navigator.pop(dContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Meal timings updated successfully!'),
                  backgroundColor: AppTheme.successGreen,
                ),
              );
            },
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text('Save Timings', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
              label: 'Breakfast Timing',
              isRequired: true,
              controller: breakfastCtrl,
              hintText: 'e.g. 7:30 AM – 9:00 AM',
              prefixIcon: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFF59E0B), size: 18),
            ),
            const SizedBox(height: 14),
            PremiumFormField(
              label: 'Lunch Timing',
              isRequired: true,
              controller: lunchCtrl,
              hintText: 'e.g. 12:30 PM – 2:00 PM',
              prefixIcon: const Icon(Icons.lunch_dining_rounded, color: Color(0xFF0D9488), size: 18),
            ),
            const SizedBox(height: 14),
            PremiumFormField(
              label: 'Dinner Timing',
              isRequired: true,
              controller: dinnerCtrl,
              hintText: 'e.g. 7:30 PM – 9:00 PM',
              prefixIcon: const Icon(Icons.dinner_dining_rounded, color: Color(0xFF6366F1), size: 18),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFoodItemDialog() {
    String selectedDay = _daysOfWeek.first;
    String selectedMeal = 'Breakfast';
    final dishesCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showPremiumDialog(
      context: context,
      builder: (dContext) => StatefulBuilder(
        builder: (context, setDState) => PremiumDialog(
          maxWidth: 480,
          title: 'Add / Quick Update Food Item',
          subtitle: 'Update menu items for a specific day and meal category',
          icon: Icons.restaurant_rounded,
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
                final dishText = dishesCtrl.text.trim();
                if (dishText.isEmpty) return;

                final mealKey = selectedMeal.toLowerCase();

                setState(() {
                  _controllers[selectedDay]![mealKey]!.text = dishText;
                });

                Navigator.pop(dContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$selectedMeal for $selectedDay updated!'),
                    backgroundColor: AppTheme.successGreen,
                  ),
                );
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text('Apply to Menu', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
              Text('Select Day', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
              const SizedBox(height: 6),
              AppDropdown.simple(
                height: 42,
                value: selectedDay,
                items: _daysOfWeek,
                onChanged: (val) => setDState(() => selectedDay = val),
              ),
              const SizedBox(height: 16),
              Text('Meal Type', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
              const SizedBox(height: 6),
              AppDropdown.simple(
                height: 42,
                value: selectedMeal,
                items: const ['Breakfast', 'Lunch', 'Dinner'],
                onChanged: (val) => setDState(() => selectedMeal = val),
              ),
              const SizedBox(height: 16),
              PremiumFormField(
                label: 'Food Item(s) & Description',
                isRequired: true,
                controller: dishesCtrl,
                hintText: 'e.g. Masala Dosa, Coconut Chutney, Sambar',
                maxLines: 2,
                prefixIcon: const Icon(Icons.fastfood_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearDay(String day) {
    showPremiumConfirmDialog(
      context: context,
      title: 'Clear $day Menu',
      message: 'Are you sure you want to clear all meal items for $day? This cannot be undone once saved.',
      confirmText: 'Clear Day',
      cancelText: 'Cancel',
      icon: Icons.delete_sweep_rounded,
      isDestructive: true,
      onConfirmAsync: () async {
        setState(() {
          _controllers[day]!['breakfast']!.clear();
          _controllers[day]!['lunch']!.clear();
          _controllers[day]!['dinner']!.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$day menu cleared.'),
              backgroundColor: AppTheme.statusRed,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textDark = isDark ? Colors.white : AppTheme.textDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 450;
                    final titleWidget = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            color: Color(0xFFEA580C),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Food Menu',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: textDark,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    );

                    final saveBtn = ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveMenu,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(_isSaving ? 'Saving...' : 'Save Menu'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 1,
                      ),
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleWidget,
                          const SizedBox(height: 12),
                          saveBtn,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        titleWidget,
                        saveBtn,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Meal Timings Banner Card
                _buildMealTimingsCard(cardBg, borderColor, textDark, isDark),
                const SizedBox(height: 24),

                // 7 Days Cards
                ..._daysOfWeek.map((day) => _buildDayCard(day, cardBg, borderColor, textDark, isDark)),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMealTimingsCard(Color cardBg, Color borderColor, Color textDark, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.primaryTeal),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Daily Dining Hours',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    onTap: _showAddFoodItemDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppTheme.primaryTeal),
                          const SizedBox(width: 4),
                          Text(
                            '+ Add Item',
                            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryTeal),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _showEditTimingsDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primaryTeal),
                          const SizedBox(width: 4),
                          Text(
                            'Edit Hours',
                            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryTeal),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final items = [
                _buildTimingBadge(
                  title: 'Breakfast',
                  time: _mealTimings['Breakfast'] ?? '7:30 AM – 9:00 AM',
                  icon: Icons.wb_sunny_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFDE68A),
                  isDark: isDark,
                ),
                _buildTimingBadge(
                  title: 'Lunch',
                  time: _mealTimings['Lunch'] ?? '12:30 PM – 2:00 PM',
                  icon: Icons.lunch_dining_rounded,
                  iconColor: const Color(0xFF0D9488),
                  bgColor: const Color(0xFFF0FDFA),
                  borderColor: const Color(0xFF99F6E4),
                  isDark: isDark,
                ),
                _buildTimingBadge(
                  title: 'Dinner',
                  time: _mealTimings['Dinner'] ?? '7:30 PM – 9:00 PM',
                  icon: Icons.dinner_dining_rounded,
                  iconColor: const Color(0xFF6366F1),
                  bgColor: const Color(0xFFEEF2FF),
                  borderColor: const Color(0xFFC7D2FE),
                  isDark: isDark,
                ),
              ];

              if (isWide) {
                return Row(
                  children: items.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: w))).toList(),
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items.map((w) => SizedBox(width: constraints.maxWidth < 450 ? constraints.maxWidth : (constraints.maxWidth - 10) / 2, child: w)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimingBadge({
    required String title,
    required String time,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF334155) : borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(
    String day,
    Color cardBg,
    Color borderColor,
    Color textDark,
    bool isDark,
  ) {
    final dayCtrls = _controllers[day]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day Header Pill & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        day,
                        style: TextStyle(
                          color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Clear $day menu',
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: AppTheme.textGrey,
                        hoverColor: AppTheme.statusRed.withValues(alpha: 0.1),
                        splashRadius: 18,
                        onPressed: () => _confirmClearDay(day),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 3 Fields: Breakfast, Lunch, Dinner
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 750;

                final breakfastField = _buildMealField(
                  label: 'Breakfast',
                  timing: _mealTimings['Breakfast'] ?? '7:30 AM – 9:00 AM',
                  controller: dayCtrls['breakfast']!,
                  icon: Icons.wb_sunny_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  bgColor: isDark ? const Color(0xFF2D2314) : const Color(0xFFFFFBEB),
                  borderColor: borderColor,
                  textDark: textDark,
                  hintText: 'e.g., Poha, Boiled Eggs & Tea',
                );

                final lunchField = _buildMealField(
                  label: 'Lunch',
                  timing: _mealTimings['Lunch'] ?? '12:30 PM – 2:00 PM',
                  controller: dayCtrls['lunch']!,
                  icon: Icons.lunch_dining_rounded,
                  iconColor: const Color(0xFF0D9488),
                  bgColor: isDark ? const Color(0xFF132B27) : const Color(0xFFF0FDFA),
                  borderColor: borderColor,
                  textDark: textDark,
                  hintText: 'e.g., Dal, Rice, Roti, Sabzi',
                );

                final dinnerField = _buildMealField(
                  label: 'Dinner',
                  timing: _mealTimings['Dinner'] ?? '7:30 PM – 9:00 PM',
                  controller: dayCtrls['dinner']!,
                  icon: Icons.dinner_dining_rounded,
                  iconColor: const Color(0xFF6366F1),
                  bgColor: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                  borderColor: borderColor,
                  textDark: textDark,
                  hintText: 'e.g., Paneer, Roti, Rice',
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: breakfastField),
                      const SizedBox(width: 14),
                      Expanded(child: lunchField),
                      const SizedBox(width: 14),
                      Expanded(child: dinnerField),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      breakfastField,
                      const SizedBox(height: 12),
                      lunchField,
                      const SizedBox(height: 12),
                      dinnerField,
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealField({
    required String label,
    required String timing,
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required Color textDark,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      timing,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(fontSize: 13.5, color: textDark),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: 13,
              color: textDark.withValues(alpha: 0.4),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
