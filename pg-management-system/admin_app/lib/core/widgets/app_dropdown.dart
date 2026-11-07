import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const AppDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// A sleek, compact SaaS filter dropdown with a white background,
/// soft grey border (AppTheme.inputBorder), rounded corners (8px),
/// Icons.keyboard_arrow_down on the right, slightly bold text,
/// rounded dropdown menu popup, and subtle shadow.
class AppDropdown<T> extends StatelessWidget {
  final T value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final double height;
  final double? width;
  final bool isExpanded;
  final IconData? leadingIcon;
  final Color? backgroundColor;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 38,
    this.width,
    this.isExpanded = true,
    this.leadingIcon,
    this.backgroundColor,
  });

  /// Factory constructor for simple string lists
  static Widget simple({
    Key? key,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    double height = 38,
    double? width,
    bool isExpanded = true,
    IconData? leadingIcon,
    Color? backgroundColor,
  }) {
    return AppDropdown<String>(
      key: key,
      value: value,
      items: items.map((s) => AppDropdownItem<String>(value: s, label: s)).toList(),
      onChanged: onChanged,
      height: height,
      width: width,
      isExpanded: isExpanded,
      leadingIcon: leadingIcon,
      backgroundColor: backgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = isDark ? const Color(0xFF334155) : AppTheme.inputBorder;
    final effectiveBgColor = backgroundColor ?? (isDark ? const Color(0xFF1E293B) : Colors.white);
    final textColor = isDark ? const Color(0xFFF1F5F9) : AppTheme.textDark;

    return Container(
      height: height,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((i) => i.value == value) ? value : (items.isNotEmpty ? items.first.value : null),
          isExpanded: isExpanded,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 20,
            color: AppTheme.textGrey,
          ),
          borderRadius: BorderRadius.circular(8),
          elevation: 3,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item.value,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingIcon != null) ...[
                    Icon(leadingIcon, size: 16, color: AppTheme.textGrey),
                    const SizedBox(width: 8),
                  ] else if (item.icon != null) ...[
                    Icon(item.icon, size: 16, color: AppTheme.textGrey),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              onChanged(val);
            }
          },
        ),
      ),
    );
  }
}
