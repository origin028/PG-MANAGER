import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Semantic type for confirmation, feedback dialogs and banners
enum PremiumDialogType {
  primary,
  destructive,
  warning,
  success,
  info,
  error,
}

/// Semantic Banner Type alias
typedef BannerType = PremiumDialogType;

/// Semantic Banner Status alias
typedef BannerStatus = PremiumDialogType;

/// Helper method to show any dialog with a premium smooth scale + fade entrance animation
Future<T?> showPremiumDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0x66000000),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim1, anim2) => builder(ctx),
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curvedValue = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ).value;

      return Transform.scale(
        scale: 0.96 + (0.04 * curvedValue),
        child: Opacity(
          opacity: curvedValue.clamp(0.0, 1.0),
          child: child,
        ),
      );
    },
  );
}

/// Helper method to quickly display a premium confirmation dialog
Future<bool?> showPremiumConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  String? subtitle,
  String confirmText = 'Confirm',
  String? confirmLabel,
  Color? confirmColor,
  String cancelText = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  PremiumDialogType type = PremiumDialogType.primary,
  dynamic detailsWidget,
  dynamic details,
  bool isDestructive = false,
  VoidCallback? onConfirm,
  Future<void> Function()? onConfirmAsync,
}) {
  final effectiveMessage = message ?? subtitle ?? '';
  final effectiveConfirmText = confirmLabel ?? confirmText;
  final effectiveType = isDestructive ? PremiumDialogType.destructive : type;

  final rawDetails = detailsWidget ?? details;
  Widget? effectiveDetailsWidget;
  if (rawDetails is Widget) {
    effectiveDetailsWidget = rawDetails;
  } else if (rawDetails is List) {
    effectiveDetailsWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (var item in rawDetails)
            if (item is Map)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.keys.first.toString(),
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: AppTheme.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      item.values.first.toString(),
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  return showPremiumDialog<bool>(
    context: context,
    builder: (ctx) => PremiumConfirmDialog(
      title: title,
      message: effectiveMessage,
      confirmText: effectiveConfirmText,
      cancelText: cancelText,
      icon: icon,
      type: effectiveType,
      detailsWidget: effectiveDetailsWidget,
      onConfirm: () {
        onConfirm?.call();
        Navigator.of(ctx).pop(true);
      },
      onConfirmAsync: onConfirmAsync,
    ),
  );
}

/// Universal Premium Dialog Container
class PremiumDialog extends StatelessWidget {
  final Widget? titleWidget;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBgColor;
  final Widget? child;
  final List<Widget>? actions;
  final double maxWidth;
  final double? maxHeight;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry contentPadding;
  final bool isScrollable;
  final Widget? customHeader;

  const PremiumDialog({
    super.key,
    this.titleWidget,
    this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.iconBgColor,
    Widget? child,
    Widget? body,
    this.actions,
    this.maxWidth = 540,
    this.maxHeight,
    this.showCloseButton = true,
    this.onClose,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 0, 24, 20),
    this.isScrollable = true,
    this.customHeader,
  }) : child = child ?? body;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground;
    final borderColor = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    final screenHeight = MediaQuery.of(context).size.height;
    final calculatedMaxHeight = maxHeight ?? (screenHeight * 0.88);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: calculatedMaxHeight,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  if (customHeader != null)
                    customHeader!
                  else if (title != null || titleWidget != null)
                    _buildDefaultHeader(context, isDark, textPri, textSec),

                  // Divider below header
                  if (title != null || titleWidget != null || customHeader != null)
                    Divider(height: 1, color: borderColor, thickness: 1),

                  // Body Content
                  Flexible(
                    child: isScrollable && child != null
                        ? SingleChildScrollView(
                            padding: contentPadding,
                            physics: const ClampingScrollPhysics(),
                            child: child!,
                          )
                        : (child != null
                            ? Padding(
                                padding: contentPadding,
                                child: child!,
                              )
                            : const SizedBox.shrink()),
                  ),

                  // Actions / Footer
                  if (actions != null && actions!.isNotEmpty) ...[
                    Divider(height: 1, color: borderColor, thickness: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: isDark ? const Color(0xFF0C191F) : const Color(0xFFF9FBFA),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final hasSpacer = actions!.any((w) => w is Spacer || w is Expanded);
                          if (hasSpacer && constraints.maxWidth >= 520) {
                            return Row(
                              children: actions!,
                            );
                          }
                          return Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: actions!.where((w) => w is! Spacer).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultHeader(
    BuildContext context,
    bool isDark,
    Color textPri,
    Color textSec,
  ) {
    final effectiveIconColor = iconColor ?? AppTheme.primaryTeal;
    final effectiveIconBg = iconBgColor ??
        (isDark
            ? AppTheme.primaryTeal.withValues(alpha: 0.2)
            : AppTheme.lightTeal);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: effectiveIconBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: effectiveIconColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(icon, color: effectiveIconColor, size: 20),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titleWidget != null)
                  titleWidget!
                else if (title != null)
                  Text(
                    title!,
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: textPri,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: textSec,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (showCloseButton)
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onClose ?? () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor,
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: textSec,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Premium Confirmation Dialog for destructive or important actions
class PremiumConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final IconData icon;
  final PremiumDialogType type;
  final Widget? detailsWidget;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final Future<void> Function()? onConfirmAsync;

  const PremiumConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
    this.icon = Icons.help_outline_rounded,
    this.type = PremiumDialogType.primary,
    this.detailsWidget,
    this.onConfirm,
    this.onCancel,
    this.onConfirmAsync,
  });

  @override
  State<PremiumConfirmDialog> createState() => _PremiumConfirmDialogState();
}

class _PremiumConfirmDialogState extends State<PremiumConfirmDialog> {
  bool _isLoading = false;

  Color _getTypeColor(bool isDark) {
    switch (widget.type) {
      case PremiumDialogType.destructive:
      case PremiumDialogType.error:
        return AppTheme.statusRed;
      case PremiumDialogType.warning:
        return AppTheme.statusAmb;
      case PremiumDialogType.success:
        return AppTheme.statusOk;
      case PremiumDialogType.info:
        return AppTheme.statusBlu;
      case PremiumDialogType.primary:
        return AppTheme.primaryTeal;
    }
  }

  Color _getTypeBgColor(bool isDark) {
    switch (widget.type) {
      case PremiumDialogType.destructive:
      case PremiumDialogType.error:
        return isDark ? const Color(0xFF3B1214) : AppTheme.statusRedSoft;
      case PremiumDialogType.warning:
        return isDark ? const Color(0xFF38230D) : AppTheme.statusAmbSoft;
      case PremiumDialogType.success:
        return isDark ? const Color(0xFF0E3324) : AppTheme.statusOkSoft;
      case PremiumDialogType.info:
        return isDark ? const Color(0xFF0F2B48) : AppTheme.statusBluSoft;
      case PremiumDialogType.primary:
        return isDark ? AppTheme.lightTealDark : AppTheme.lightTeal;
    }
  }

  Future<void> _handleConfirm() async {
    if (_isLoading) return;
    if (widget.onConfirmAsync != null) {
      setState(() => _isLoading = true);
      try {
        await widget.onConfirmAsync!();
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Action failed: $e'),
              backgroundColor: AppTheme.statusRed,
            ),
          );
        }
      }
    } else if (widget.onConfirm != null) {
      widget.onConfirm!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground;
    final borderColor = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    final typeColor = _getTypeColor(isDark);
    final typeBg = _getTypeBgColor(isDark);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.09),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon + Title Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: typeBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: typeColor.withValues(alpha: 0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(widget.icon, color: typeColor, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                widget.title,
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: textPri,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.message,
                                style: GoogleFonts.manrope(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: textSec,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (widget.detailsWidget != null) ...[
                      const SizedBox(height: 16),
                      widget.detailsWidget!,
                    ],

                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : (widget.onCancel ?? () => Navigator.of(context).pop(false)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textSec,
                            side: BorderSide(color: borderColor, width: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            widget.cancelText,
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: typeColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: typeColor.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  widget.confirmText,
                                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standardized Form Input Field for Popups
class PremiumFormField extends StatelessWidget {
  final String? label;
  final bool isRequired;
  final TextEditingController? controller;
  final String? hintText;
  final String? initialValue;
  final dynamic prefixIcon;
  final dynamic suffixIcon;
  final String? prefixText;
  final int maxLines;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool readOnly;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final VoidCallback? onTap;
  final String? errorMessage;

  const PremiumFormField({
    super.key,
    this.label,
    bool isRequired = false,
    bool? required,
    this.controller,
    this.hintText,
    this.initialValue,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.readOnly = false,
    this.validator,
    this.onChanged,
    this.onTap,
    this.errorMessage,
  }) : isRequired = required ?? isRequired;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;
    final borderColor = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final fieldBg = isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground;

    Widget? resolvedPrefix;
    if (prefixIcon is IconData) {
      resolvedPrefix = Icon(prefixIcon as IconData, size: 18, color: textSec);
    } else if (prefixIcon is Widget) {
      resolvedPrefix = prefixIcon as Widget;
    }

    Widget? resolvedSuffix;
    if (suffixIcon is IconData) {
      resolvedSuffix = Icon(suffixIcon as IconData, size: 18, color: textSec);
    } else if (suffixIcon is Widget) {
      resolvedSuffix = suffixIcon as Widget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          RichText(
            text: TextSpan(
              text: label!,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textPri,
              ),
              children: [
                if (isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: AppTheme.statusRed,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          initialValue: initialValue,
          maxLines: maxLines,
          keyboardType: keyboardType,
          obscureText: obscureText,
          readOnly: readOnly,
          validator: validator,
          onChanged: onChanged,
          onTap: onTap,
          style: GoogleFonts.manrope(
            fontSize: 13.5,
            color: textPri,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.manrope(
              fontSize: 13,
              color: textSec.withValues(alpha: 0.7),
            ),
            prefixIcon: resolvedPrefix,
            suffixIcon: resolvedSuffix,
            prefixText: prefixText,
            prefixStyle: GoogleFonts.manrope(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: textPri,
            ),
            errorText: errorMessage,
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.statusRed, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.statusRed, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standard Section Header for Popup forms
class PremiumSectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;

  const PremiumSectionTitle({
    super.key,
    required this.title,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppTheme.primaryTeal),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryTeal,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status / Info Banner inside Dialogs
class PremiumDialogBanner extends StatelessWidget {
  final String message;
  final String? title;
  final IconData? icon;
  final PremiumDialogType type;
  final BannerType? bannerType;
  final BannerStatus? status;

  const PremiumDialogBanner({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.type = PremiumDialogType.info,
    this.bannerType,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color color;
    Color bg;
    IconData defaultIcon;

    final resolvedType = bannerType != null
        ? (bannerType == BannerType.error
            ? PremiumDialogType.destructive
            : (bannerType == BannerType.warning
                ? PremiumDialogType.warning
                : (bannerType == BannerType.success
                    ? PremiumDialogType.success
                    : (bannerType == BannerType.primary
                        ? PremiumDialogType.primary
                        : PremiumDialogType.info))))
        : (status != null
            ? (status == BannerStatus.error
                ? PremiumDialogType.destructive
                : (status == BannerStatus.warning
                    ? PremiumDialogType.warning
                    : (status == BannerStatus.success
                        ? PremiumDialogType.success
                        : (status == BannerStatus.primary
                            ? PremiumDialogType.primary
                            : PremiumDialogType.info))))
            : type);

    switch (resolvedType) {
      case PremiumDialogType.destructive:
      case PremiumDialogType.error:
        color = AppTheme.statusRed;
        bg = isDark ? const Color(0xFF381416) : AppTheme.statusRedSoft;
        defaultIcon = Icons.error_outline_rounded;
        break;
      case PremiumDialogType.warning:
        color = AppTheme.statusAmb;
        bg = isDark ? const Color(0xFF38230D) : AppTheme.statusAmbSoft;
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case PremiumDialogType.success:
        color = AppTheme.statusOk;
        bg = isDark ? const Color(0xFF0F3625) : AppTheme.statusOkSoft;
        defaultIcon = Icons.check_circle_outline_rounded;
        break;
      case PremiumDialogType.info:
        color = AppTheme.statusBlu;
        bg = isDark ? const Color(0xFF102D4C) : AppTheme.statusBluSoft;
        defaultIcon = Icons.info_outline_rounded;
        break;
      case PremiumDialogType.primary:
        color = AppTheme.primaryTeal;
        bg = isDark ? AppTheme.lightTealDark : AppTheme.lightTeal;
        defaultIcon = Icons.info_outline_rounded;
        break;
    }

    final effectiveIcon = icon ?? defaultIcon;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(effectiveIcon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: GoogleFonts.manrope(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: GoogleFonts.manrope(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
