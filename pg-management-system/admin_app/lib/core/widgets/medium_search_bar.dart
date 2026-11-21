import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class MediumSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hintText;
  final double maxWidth;

  const MediumSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.onClear,
    this.hintText = 'Search...',
    this.maxWidth = 360,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderCol = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : Colors.white;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final hintCol = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textPri,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: hintCol,
            ),
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: hintCol),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded, size: 16, color: hintCol),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      controller.clear();
                      if (onChanged != null) onChanged!('');
                      if (onClear != null) onClear!();
                    },
                  )
                : null,
            filled: true,
            fillColor: cardBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderCol),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderCol),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

