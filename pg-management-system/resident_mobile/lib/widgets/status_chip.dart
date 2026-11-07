import 'package:flutter/material.dart';
import '../core/theme.dart';

class StatusChip extends StatelessWidget {
  final String status;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const StatusChip({
    super.key,
    required this.status,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  Color _getStatusColor(String s) {
    final upper = s.toUpperCase();
    switch (upper) {
      case 'PAID':
      case 'SUCCESS':
      case 'DELIVERED':
      case 'GENERATED':
        return AppTheme.statusPaid;
      case 'PENDING':
      case 'PROCESSING':
        return AppTheme.statusPending;
      case 'OVERDUE':
      case 'FAILED':
      case 'EXPIRED':
        return AppTheme.statusOverdue;
      case 'PARTIALLY_PAID':
      case 'PARTIAL':
        return AppTheme.statusPartial;
      case 'CANCELLED':
      case 'REFUNDED':
        return AppTheme.textSecondary;
      default:
        return AppTheme.primaryLight;
    }
  }

  String _formatStatus(String s) {
    if (s.isEmpty) return '';
    return s.replaceAll('_', ' ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor(status);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
