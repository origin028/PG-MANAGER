import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AppLoader extends StatelessWidget {
  final String? message;
  const AppLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primaryTeal,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
