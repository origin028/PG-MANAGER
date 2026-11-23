import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// 1. KPI Summary Card for Table Screens (Matching PG_Pilot_Admin_Pro.html stat card)
class TableKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String? subtitle;

  const TableKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground;
    final borderCol = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0E1A1F).withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    color: textSec,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    color: textPri,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: GoogleFonts.manrope(
                      color: textSec,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
        ],
      ),
    );
  }
}

/// Responsive Grid / Row of KPI Cards
class TableKpiGrid extends StatelessWidget {
  final List<TableKpiCard> cards;

  const TableKpiGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 600) {
          // Mobile: horizontal scrollable row of compact cards
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cards.map((c) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 175,
                  child: c,
                ),
              )).toList(),
            ),
          );
        } else if (width < 950) {
          // Tablet: 2 columns
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((c) => SizedBox(
              width: (width - 12) / 2,
              child: c,
            )).toList(),
          );
        } else {
          // Desktop: Row
          return Row(
            children: cards.asMap().entries.map((entry) {
              final idx = entry.key;
              final card = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: idx == 0 ? 0 : 12),
                  child: card,
                ),
              );
            }).toList(),
          );
        }
      },
    );
  }
}

/// 4. Polished Status Pill (Matching PG_Pilot_Admin_Pro.html .chip)
class StatusPill extends StatelessWidget {
  final String status;
  final Color? color;
  final Color? backgroundColor;
  final bool showDot;

  const StatusPill({
    super.key,
    required this.status,
    this.color,
    this.backgroundColor,
    this.showDot = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color textColor;
    Color bgColor;

    final lower = status.toLowerCase();
    if (color != null && backgroundColor != null) {
      textColor = color!;
      bgColor = backgroundColor!;
    } else if (lower == 'active' || lower == 'paid' || lower == 'resolved' || lower == 'converted' || lower == 'verified') {
      textColor = isDark ? const Color(0xFF6FD6A8) : AppTheme.statusOk;
      bgColor = isDark ? const Color(0xFF12342A) : AppTheme.statusOkSoft;
    } else if (lower == 'pending' || lower == 'in progress' || lower == 'visit scheduled' || lower == 'medium' || lower == 'maintenance' || lower == 'on leave' || lower == 'notice period' || lower == 'partial') {
      textColor = isDark ? const Color(0xFFF5C26B) : AppTheme.statusAmb;
      bgColor = isDark ? const Color(0xFF3A2C0E) : AppTheme.statusAmbSoft;
    } else if (lower == 'high' || lower == 'lost' || lower == 'overdue' || lower == 'rejected' || lower == 'inactive' || lower == 'assigned') {
      textColor = isDark ? const Color(0xFFFF9A8F) : AppTheme.statusRed;
      bgColor = isDark ? const Color(0xFF3C1A17) : AppTheme.statusRedSoft;
    } else if (lower == 'new' || lower == 'contacted' || lower == 'low') {
      textColor = isDark ? const Color(0xFF8EC2F5) : AppTheme.statusBlu;
      bgColor = isDark ? const Color(0xFF12304D) : AppTheme.statusBluSoft;
    } else {
      // Muted default (checked out, neutral, etc.)
      textColor = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;
      bgColor = isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20), // Pill / Chip shape
        border: Border.all(color: textColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            status,
            maxLines: 1,
            style: GoogleFonts.manrope(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3. Avatar with initials and pastel background (Matching reference TINT)
class TableAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const TableAvatar({super.key, required this.name, this.radius = 16});

  static const List<List<Color>> _tintPairs = [
    [Color(0xFFFEF3C7), Color(0xFF92400E)], // amber
    [Color(0xFFDDF3E8), Color(0xFF0F6B4A)], // emerald
    [Color(0xFFE1EEFB), Color(0xFF0B5CAD)], // blue
    [Color(0xFFEDE4FB), Color(0xFF5B2FA8)], // purple
    [Color(0xFFFDE8E6), Color(0xFFB42318)], // red
  ];

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim();
    final letter = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : '?';
    final index = cleanName.isEmpty ? 0 : cleanName.codeUnitAt(0) % _tintPairs.length;
    final pair = _tintPairs[index];

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: pair[0],
        borderRadius: BorderRadius.circular(10), // Modern rounded square
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.manrope(
          color: pair[1],
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

/// Action Button with subtle border and soft hover (Matching reference .ic)
class TableActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const TableActionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderCol = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderCol),
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: color ?? (isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText)),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        splashRadius: 16,
      ),
    );
  }
}

/// Shared Table Container Box Decoration
BoxDecoration get modernTableDecoration => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: AppTheme.borderColor),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF0E1A1F).withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ],
);

/// Shared Table Header Column helper
DataColumn modernTableColumn(String label) {
  return DataColumn(
    label: Text(
      label.toUpperCase(),
      style: GoogleFonts.manrope(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppTheme.secondaryText,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// Shared DataRow hover color
WidgetStateProperty<Color?> get modernRowColor {
  return WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.hovered)) {
      return AppTheme.softBackground;
    }
    return Colors.white;
  });
}
