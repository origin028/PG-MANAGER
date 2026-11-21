import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppTheme.primaryTeal),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: textPri,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                color: textSec,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(
                  actionLabel!,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
