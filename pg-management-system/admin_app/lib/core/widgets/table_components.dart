import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 1. KPI Summary Card for Table Screens
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
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
                  width: 170,
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

/// 4. Polished Status Pill (Linear / Stripe style)
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
    Color textColor;
    Color bgColor;

    final lower = status.toLowerCase();
    if (color != null && backgroundColor != null) {
      textColor = color!;
      bgColor = backgroundColor!;
    } else if (lower == 'active' || lower == 'paid' || lower == 'resolved' || lower == 'converted' || lower == 'verified') {
      textColor = const Color(0xFF059669); // Green 600
      bgColor = const Color(0xFFECFDF5);  // Green 50
    } else if (lower == 'pending' || lower == 'in progress' || lower == 'visit scheduled' || lower == 'medium' || lower == 'maintenance' || lower == 'on leave') {
      textColor = const Color(0xFFD97706); // Amber 600
      bgColor = const Color(0xFFFFFBEB);  // Amber 50
    } else if (lower == 'high' || lower == 'lost' || lower == 'overdue' || lower == 'rejected' || lower == 'inactive') {
      textColor = const Color(0xFFDC2626); // Red 600
      bgColor = const Color(0xFFFEF2F2);  // Red 50
    } else {
      // Default: Blue / Slate
      textColor = const Color(0xFF2563EB); // Blue 600
      bgColor = const Color(0xFFEFF6FF);  // Blue 50
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20), // Pill shape
        border: Border.all(color: textColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
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
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3. Avatar with initials and pastel background
class TableAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const TableAvatar({super.key, required this.name, this.radius = 16});

  static const List<Color> _bgColors = [
    Color(0xFFEFF6FF), // soft blue
    Color(0xFFF5F3FF), // soft purple
    Color(0xFFECFDF5), // soft emerald
    Color(0xFFFFFBEB), // soft amber
    Color(0xFFFDF2F8), // soft pink
    Color(0xFFF0FDF4), // soft green
    Color(0xFFF8FAFC), // soft slate
  ];

  static const List<Color> _textColors = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFFDB2777),
    Color(0xFF16A34A),
    Color(0xFF475569),
  ];

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim();
    final letter = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : '?';
    final index = cleanName.isEmpty ? 0 : cleanName.codeUnitAt(0) % _bgColors.length;

    return CircleAvatar(
      radius: radius,
      backgroundColor: _bgColors[index],
      child: Text(
        letter,
        style: TextStyle(
          color: _textColors[index],
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

/// Action Button with subtle border and soft hover
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: color ?? const Color(0xFF64748B)),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        splashRadius: 18,
      ),
    );
  }
}

/// Shared Table Container Box Decoration
BoxDecoration get modernTableDecoration => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: const Color(0xFFE2E8F0)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ],
);

/// Shared Table Header Column helper
DataColumn modernTableColumn(String label) {
  return DataColumn(
    label: Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.textGrey,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// Shared DataRow hover color
WidgetStateProperty<Color?> get modernRowColor {
  return WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.hovered)) {
      return const Color(0xFFF8FAFC);
    }
    return Colors.white;
  });
}
