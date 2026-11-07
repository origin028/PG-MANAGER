import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';

class FoodMenuScreen extends StatefulWidget {
  const FoodMenuScreen({super.key});

  @override
  State<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends State<FoodMenuScreen> {
  // Map of controllers for each day: { 'Monday': { 'breakfast': controller, 'lunch': controller, 'dinner': controller } }
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

  @override
  void initState() {
    super.initState();
    _initControllers();
    AppData.selectedPropertyIdNotifier.addListener(_loadMenuFromApi);
    _loadMenuFromApi();
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
            constraints: const BoxConstraints(maxWidth: 1000),
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
                        backgroundColor: AppTheme.primaryBlue,
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
                const SizedBox(height: 24),

                // 7 Days Cards
                ..._daysOfWeek.map((day) => _buildDayCard(day, cardBg, borderColor, textDark, isDark)),

                const SizedBox(height: 24),

                // Bottom Save Button for convenient access
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveMenu,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(
                      _isSaving ? 'Saving Menu...' : 'Save Weekly Menu',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
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
            // Day Header Pill
            Row(
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
              ],
            ),
            const SizedBox(height: 18),

            // 3 Fields: Breakfast, Lunch, Dinner
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildMealField(
                          label: 'Breakfast',
                          controller: dayCtrls['breakfast']!,
                          icon: Icons.wb_sunny_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          bgColor: isDark ? const Color(0xFF2D2314) : const Color(0xFFFFFBEB),
                          borderColor: borderColor,
                          textDark: textDark,
                          hintText: 'e.g., Poha & Tea',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildMealField(
                          label: 'Lunch',
                          controller: dayCtrls['lunch']!,
                          icon: Icons.lunch_dining_rounded,
                          iconColor: const Color(0xFF0D9488),
                          bgColor: isDark ? const Color(0xFF132B27) : const Color(0xFFF0FDFA),
                          borderColor: borderColor,
                          textDark: textDark,
                          hintText: 'e.g., Dal, Rice, Roti, Sabzi',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildMealField(
                          label: 'Dinner',
                          controller: dayCtrls['dinner']!,
                          icon: Icons.dinner_dining_rounded,
                          iconColor: const Color(0xFF6366F1),
                          bgColor: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                          borderColor: borderColor,
                          textDark: textDark,
                          hintText: 'e.g., Paneer, Roti, Rice',
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildMealField(
                        label: 'Breakfast',
                        controller: dayCtrls['breakfast']!,
                        icon: Icons.wb_sunny_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        bgColor: isDark ? const Color(0xFF2D2314) : const Color(0xFFFFFBEB),
                        borderColor: borderColor,
                        textDark: textDark,
                        hintText: 'e.g., Poha & Tea',
                      ),
                      const SizedBox(height: 12),
                      _buildMealField(
                        label: 'Lunch',
                        controller: dayCtrls['lunch']!,
                        icon: Icons.lunch_dining_rounded,
                        iconColor: const Color(0xFF0D9488),
                        bgColor: isDark ? const Color(0xFF132B27) : const Color(0xFFF0FDFA),
                        borderColor: borderColor,
                        textDark: textDark,
                        hintText: 'e.g., Dal, Rice, Roti, Sabzi',
                      ),
                      const SizedBox(height: 12),
                      _buildMealField(
                        label: 'Dinner',
                        controller: dayCtrls['dinner']!,
                        icon: Icons.dinner_dining_rounded,
                        iconColor: const Color(0xFF6366F1),
                        bgColor: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                        borderColor: borderColor,
                        textDark: textDark,
                        hintText: 'e.g., Paneer, Roti, Rice',
                      ),
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
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: textDark,
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
              borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
