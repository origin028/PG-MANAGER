import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/app_data.dart';
import '../theme/app_theme.dart';
import '../services/admin_api_service.dart';
import '../services/admin_auth_service.dart';
import 'app_dropdown.dart';
import 'premium_dialogs.dart';
import '../../features/properties/property_form_dialog.dart';

class AdminLayout extends StatefulWidget {
  final Widget child;
  const AdminLayout({super.key, required this.child});

  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout> {
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final properties = await AdminApiService.getProperties();
      if (mounted && properties.isNotEmpty) {
        setState(() {
          AppData.setRealProperties(properties);
        });
      }
      final notifs = await AdminApiService.getNotifications();
      if (mounted && notifs.isNotEmpty) {
        setState(() {
          AppData.adminNotifications = notifs;
        });
      }
    } catch (_) {}
  }

  void _showAddPropertyDialog(BuildContext context) {
    showAddEditPropertyDialog(
      context: context,
      onSaved: () {
        setState(() {});
      },
    );
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showPremiumConfirmDialog(
      context: context,
      title: 'Confirm Logout',
      message: 'Are you sure you want to log out of PG Owner? You will need to sign in again to access the admin portal.',
      confirmText: 'Log Out',
      cancelText: 'Cancel',
      icon: Icons.logout_rounded,
      isDestructive: true,
      onConfirmAsync: () async {
        await AdminAuthService.logout();
        if (context.mounted) {
          context.go('/login');
        }
      },
    );
  }

  void _showNotificationsModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground;
    final borderCol = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final notifs = AppData.adminNotifications;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.78,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(
                      top: BorderSide(color: borderCol, width: 1.2),
                      left: BorderSide(color: borderCol, width: 1.2),
                      right: BorderSide(color: borderCol, width: 1.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                        blurRadius: 30,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Modern Drag Handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          margin: const EdgeInsets.only(top: 12, bottom: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryTeal, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    children: [
                                      Text(
                                        'Notifications',
                                        style: GoogleFonts.manrope(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                          color: textPri,
                                        ),
                                      ),
                                      if (notifs.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDC2626),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${notifs.length} new',
                                            style: GoogleFonts.manrope(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    notifs.isEmpty
                                        ? 'No new notifications'
                                        : 'Alerts and resident registrations',
                                    style: GoogleFonts.manrope(fontSize: 12, color: textSec, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            if (notifs.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    AppData.adminNotifications.clear();
                                  });
                                  setModalState(() {});
                                },
                                child: Text(
                                  'Clear All',
                                  style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                                ),
                              ),
                            IconButton(
                              icon: Icon(Icons.close_rounded, color: textSec),
                              onPressed: () => Navigator.pop(sheetContext),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderCol),

                      // Content
                      Expanded(
                        child: notifs.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.done_all_rounded, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText, size: 36),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        "You're All Caught Up!",
                                        style: GoogleFonts.manrope(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: textPri,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'No unread notifications at the moment.',
                                        style: GoogleFonts.manrope(fontSize: 13, color: textSec),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: notifs.length,
                                separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                                itemBuilder: (ctx, index) {
                                  final n = notifs[index];
                                  final title = n['title'] ?? 'Notification';
                                  final message = n['message'] ?? '';
                                  final time = n['time'] ?? 'Just now';

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryTeal, size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      style: GoogleFonts.manrope(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 13.5,
                                                        color: textPri,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    time,
                                                    style: GoogleFonts.manrope(fontSize: 11, color: textSec),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                message,
                                                style: GoogleFonts.manrope(fontSize: 12.5, color: textSec, height: 1.35),
                                              ),
                                              const SizedBox(height: 8),
                                              InkWell(
                                                onTap: () {
                                                  Navigator.pop(sheetContext);
                                                  context.go('/residents');
                                                },
                                                borderRadius: BorderRadius.circular(6),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          'View in Residents',
                                                          style: GoogleFonts.manrope(
                                                            fontSize: 12,
                                                            color: AppTheme.primaryTeal,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      const Icon(Icons.arrow_forward_rounded, size: 12, color: AppTheme.primaryTeal),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGlobalHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = isDark ? AppTheme.borderColorDark : AppTheme.borderColor;
    final cardBg = isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground;
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    if (!isDesktop) {
      // -------------------------------------------------------------
      // 1. MOBILE HEADER (Screen width < 800px)
      // -------------------------------------------------------------
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          border: Border(
            bottom: BorderSide(
              color: borderCol,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0E1A1F).withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Hamburger + Logo + Title | Bell + Add Property
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      width: constraints.maxWidth,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left: Hamburger (☰) + Logo + Title
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Builder(
                                    builder: (scaffoldContext) => IconButton(
                                      icon: Icon(
                                        Icons.menu_rounded,
                                        color: textPri,
                                        size: 26,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      tooltip: 'Menu',
                                      onPressed: () {
                                        Scaffold.of(scaffoldContext).openDrawer();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [AppTheme.brightTeal, AppTheme.primaryTeal],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 19),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'PG Pilot',
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: textPri,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),

                              // Right: Notification Bell + Compact [+ Add Property]
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.notifications_none_rounded,
                                          color: textPri,
                                          size: 24,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                        tooltip: 'Notifications',
                                        onPressed: () => _showNotificationsModal(context),
                                      ),
                                      if (AppData.adminNotifications.isNotEmpty)
                                        Positioned(
                                          right: 2,
                                          top: 2,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFDC2626),
                                              shape: BoxShape.circle,
                                            ),
                                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                            child: Text(
                                              '${AppData.adminNotifications.length}',
                                              style: GoogleFonts.manrope(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _showAddPropertyDialog(context),
                                    icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                                    label: Text(
                                      constraints.maxWidth < 310 ? 'Add' : 'Add Property',
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryTeal,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth < 310 ? 8 : 12, vertical: 8),
                                      minimumSize: const Size(0, 36),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      elevation: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),

                // Row 2: Greeting & Date Pill
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Good morning',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderCol),
                        ),
                        child: Text(
                          'Wednesday, October 28',
                          style: GoogleFonts.manrope(
                            color: textSec,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Row 3: Property Switcher
                SizedBox(
                  width: double.infinity,
                  child: AppDropdown<String>(
                    height: 38,
                    isExpanded: true,
                    value: AppData.propertyNames.contains(AppData.selectedProperty)
                        ? AppData.selectedProperty
                        : AppData.propertyNames.first,
                    items: AppData.propertyNames
                        .map((p) => AppDropdownItem<String>(
                              value: p,
                              label: p,
                              icon: Icons.apartment_rounded,
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        AppData.selectPropertyByName(val);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // -----------------------------------------------------------------
    // 2. DESKTOP HEADER (Screen width >= 800px)
    // -----------------------------------------------------------------
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(
          bottom: BorderSide(
            color: borderCol,
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, headerConstraints) {
          return SizedBox(
            width: headerConstraints.maxWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: headerConstraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left: Greeting, Date, Property Dropdown in a single horizontal row
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Good morning',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textPri,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.only(left: 14),
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: borderCol)),
                          ),
                          child: Text(
                            'Wednesday, October 28',
                            style: GoogleFonts.manrope(
                              color: textSec,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        AppDropdown<String>(
                          height: 38,
                          isExpanded: false,
                          value: AppData.propertyNames.contains(AppData.selectedProperty)
                              ? AppData.selectedProperty
                              : AppData.propertyNames.first,
                          items: AppData.propertyNames
                              .map((p) => AppDropdownItem<String>(
                                    value: p,
                                    label: p,
                                    icon: Icons.apartment_rounded,
                                  ))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              AppData.selectPropertyByName(val);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Right: Notification Bell + Add Property Button
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.notifications_none_rounded,
                                color: textPri,
                                size: 23,
                              ),
                              tooltip: 'Notifications',
                              onPressed: () => _showNotificationsModal(context),
                            ),
                            if (AppData.adminNotifications.isNotEmpty)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  child: Text(
                                    '${AppData.adminNotifications.length}',
                                    style: GoogleFonts.manrope(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showAddPropertyDialog(context),
                          icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          label: Text(
                            'Add Property',
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: !isDesktop ? Drawer(child: _buildSidebar(context)) : null,
      appBar: null,
      body: Row(
        children: [
          // Desktop Sidebar
          if (isDesktop)
            Container(
              width: 252,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryNavy,
                    AppTheme.darkNavy,
                  ],
                ),
              ),
              child: _buildSidebar(context),
            ),
          
          // Main Content with Global Header on Top
          Expanded(
            child: Column(
              children: [
                _buildGlobalHeader(context, isDesktop),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primaryNavy,
            AppTheme.darkNavy,
          ],
        ),
      ),
      child: Column(
        children: [
          // Brand Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.brightTeal, AppTheme.primaryTeal],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Center(
                    child: Icon(Icons.apartment_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PG Owner',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'PG Pilot admin',
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7FA0AB),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 8),
          
          // Navigation List
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(Icons.grid_view_rounded, 'Dashboard', '/dashboard', context),
                _buildMenuItem(Icons.apartment_rounded, 'Properties', '/properties', context),
                _buildMenuItem(Icons.hotel_rounded, 'Rooms & Beds', '/rooms', context),
                _buildMenuItem(Icons.groups_rounded, 'Residents', '/residents', context),
                _buildMenuItem(Icons.credit_card_rounded, 'Payments', '/payments', context),
                _buildMenuItem(Icons.receipt_long_rounded, 'Expenses', '/expenses', context),
                _buildMenuItem(Icons.campaign_rounded, 'Announcements', '/announcements', context),
                _buildMenuItem(Icons.badge_rounded, 'Staff', '/staff', context),
                _buildMenuItem(Icons.restaurant_menu_rounded, 'Food Menu', '/food-menu', context),
                _buildMenuItem(Icons.warning_amber_rounded, 'Complaints', '/complaints', context),
                _buildMenuItem(Icons.bar_chart_rounded, 'Reports', '/reports', context),
                _buildMenuItem(Icons.settings_outlined, 'Settings', '/settings', context),
              ],
            ),
          ),
          
          // User Profile Card at Sidebar Bottom (Matching .me in reference)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppTheme.brightTeal,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      'OM',
                      style: GoogleFonts.manrope(
                        color: const Color(0xFF052B27),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (MediaQuery.of(context).size.width < 800) {
                        Navigator.pop(context);
                      }
                      context.go('/settings');
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Owner Manager',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'PG Owner (Admin)',
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF7FA0AB),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Gear / Settings Icon
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18, color: Color(0xFF9DB4BC)),
                  tooltip: 'Settings',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    if (MediaQuery.of(context).size.width < 800) {
                      Navigator.pop(context);
                    }
                    context.go('/settings');
                  },
                ),
                // Logout Icon
                IconButton(
                  icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF9DB4BC)),
                  tooltip: 'Log Out',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showLogoutConfirmDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, String route, BuildContext context) {
    final currentRoute = GoRouterState.of(context).uri.toString();
    final isActive = currentRoute == route;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: isActive 
            ? const Color(0x1A5EEAD4) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          onTap: () {
            if (MediaQuery.of(context).size.width < 800) {
              Navigator.pop(context);
            }
            context.go(route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isActive)
                  Container(
                    width: 3,
                    height: 18,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.glowTeal,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  const SizedBox(width: 11),
                Icon(
                  icon, 
                  color: isActive ? AppTheme.glowTeal : const Color(0xFF9DB4BC), 
                  size: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: isActive ? Colors.white : const Color(0xFF9DB4BC),
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
