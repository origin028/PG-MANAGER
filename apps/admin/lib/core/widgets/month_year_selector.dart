import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class MonthYearSelector extends StatelessWidget {
  final int selectedMonth;
  final int selectedYear;
  final void Function(int month, int year) onChanged;

  const MonthYearSelector({
    super.key,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onChanged,
  });

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderCol = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : Colors.white;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;

    final currentYear = DateTime.now().year;
    // Provide years from 2023 to currentYear + 1 (e.g. 2027)
    final years = List.generate(
      (currentYear + 1) - 2023 + 1,
      (index) => 2023 + index,
    ).reversed.toList();

    final safeMonthIndex = (selectedMonth >= 1 && selectedMonth <= 12) ? selectedMonth - 1 : 0;
    final monthName = _months[safeMonthIndex];

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            size: 15,
            color: AppTheme.primaryTeal,
          ),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: monthName,
              isDense: true,
              icon: Icon(Icons.arrow_drop_down_rounded, size: 18, color: textPri),
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
              dropdownColor: cardBg,
              selectedItemBuilder: (BuildContext context) {
                return _months.map<Widget>((String m) {
                  return Center(
                    child: Text(
                      m.length > 3 ? m.substring(0, 3) : m,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                      ),
                    ),
                  );
                }).toList();
              },
              items: _months.map((m) {
                return DropdownMenuItem<String>(
                  value: m,
                  child: Text(m, style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPri)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  final newMonth = _months.indexOf(val) + 1;
                  onChanged(newMonth, selectedYear);
                }
              },
            ),
          ),
          Container(
            height: 14,
            width: 1,
            color: borderCol,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: years.contains(selectedYear) ? selectedYear : currentYear,
              isDense: true,
              icon: Icon(Icons.arrow_drop_down_rounded, size: 18, color: textPri),
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
              dropdownColor: cardBg,
              items: years.map((y) {
                return DropdownMenuItem<int>(
                  value: y,
                  child: Text('$y', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPri)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  onChanged(selectedMonth, val);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
