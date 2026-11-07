import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/app_data.dart';
import '../theme/app_theme.dart';
import '../services/admin_api_service.dart';
import '../services/admin_auth_service.dart';
import 'app_dropdown.dart';
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

  void _showNotificationsModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;

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
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 20),
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
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
                                            style: const TextStyle(
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
                                    style: TextStyle(fontSize: 12, color: textSec),
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
                                child: const Text(
                                  'Clear All',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
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
                                          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.done_all_rounded, color: isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey, size: 36),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        "You're All Caught Up!",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: textPri,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'No unread notifications at the moment.',
                                        style: TextStyle(fontSize: 13, color: textSec),
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
                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 18),
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
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13.5,
                                                        color: textPri,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    time,
                                                    style: TextStyle(fontSize: 11, color: textSec),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                message,
                                                style: TextStyle(fontSize: 12.5, color: textSec, height: 1.35),
                                              ),
                                              const SizedBox(height: 8),
                                              InkWell(
                                                onTap: () {
                                                  Navigator.pop(sheetContext);
                                                  context.go('/residents');
                                                },
                                                borderRadius: BorderRadius.circular(6),
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 2),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          'View in Residents',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: AppTheme.primaryBlue,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      SizedBox(width: 4),
                                                      Icon(Icons.arrow_forward_rounded, size: 12, color: AppTheme.primaryBlue),
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

    if (!isDesktop) {
      // -------------------------------------------------------------
      // 1. MOBILE HEADER (Screen width < 800px)
      // -------------------------------------------------------------
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
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
                // -------------------------------------------------------------
                // Row 1 (Top Bar):
                // Left side: The Hamburger Menu (☰) + the App Logo.
                // Right side: Notification Bell (with a red badge if unread) +
                // a compact [+ Add Property] button (wrap content, no stretch).
                // -------------------------------------------------------------
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
                              // Left side: Hamburger (☰) + App Logo
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Builder(
                                    builder: (scaffoldContext) => IconButton(
                                      icon: Icon(
                                        Icons.menu_rounded,
                                        color: isDark ? Colors.white : AppTheme.textDark,
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
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.home_work_rounded, color: AppTheme.primaryBlue, size: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'PG Pilot',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? Colors.white : AppTheme.textDark,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),

                              // Right side: Notification Bell + Compact [+ Add Property]
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.notifications_none_rounded,
                                          color: isDark ? Colors.white : AppTheme.textDark,
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
                                              style: const TextStyle(
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
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth < 310 ? 8 : 12, vertical: 8),
                                      minimumSize: const Size(0, 36),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

                // -------------------------------------------------------------
                // Row 2 (Greeting & Date):
                // 'Good morning' (bold) and the Date pill sitting next to it.
                // -------------------------------------------------------------
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Good morning',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          'Wednesday, October 28',
                          style: TextStyle(
                            color: isDark ? const Color(0xFFCBD5E1) : AppTheme.textGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // -------------------------------------------------------------
                // Row 3 (Property Switcher):
                // The 'Green View PG - Hebbal' dropdown, taking full width.
                // -------------------------------------------------------------
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            'Wednesday, October 28',
                            style: TextStyle(
                              color: isDark ? const Color(0xFFCBD5E1) : AppTheme.textGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
                                color: isDark ? Colors.white : AppTheme.textDark,
                                size: 24,
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
                                    style: const TextStyle(
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
                          icon: const Icon(Icons.add, size: 16, color: Colors.white),
                          label: const Text(
                            'Add Property',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: !isDesktop ? Drawer(child: _buildSidebar(context)) : null,
      appBar: null,
      body: Row(
        children: [
          // Desktop Sidebar
          if (isDesktop)
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border(
                  right: BorderSide(
                    color: isDark ? const Color(0xFF334155) : Colors.black.withValues(alpha: 0.04),
                    width: 1,
                  ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.domain_rounded, color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'PG Owner',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : AppTheme.textDark,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          
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
                _buildMenuItem(Icons.badge_rounded, 'Staff', '/staff', context),
                _buildMenuItem(Icons.restaurant_menu_rounded, 'Food Menu', '/food-menu', context),
                _buildMenuItem(Icons.warning_amber_rounded, 'Complaints', '/complaints', context),
                _buildMenuItem(Icons.trending_up_rounded, 'Leads', '/leads', context),
                _buildMenuItem(Icons.bar_chart_rounded, 'Reports', '/reports', context),
                _buildMenuItem(Icons.settings_outlined, 'Settings', '/settings', context),
              ],
            ),
          ),
          
          // User Profile Card at Sidebar Bottom
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                  width: 1,
                ),
              ),
            ),
            child: InkWell(
              onTap: () {
                if (MediaQuery.of(context).size.width < 800) {
                  Navigator.pop(context);
                }
                context.go('/settings');
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Profile',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? Colors.white : AppTheme.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PG Owner (Admin)',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey,
                      ),
                      tooltip: 'Log Out',
                      onPressed: () async {
                        await AdminAuthService.logout();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, String route, BuildContext context) {
    final isActive = GoRouterState.of(context).uri.toString() == route;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Material(
        color: isActive 
            ? (isDark ? const Color(0xFF2563EB).withValues(alpha: 0.25) : AppTheme.primaryLight) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (MediaQuery.of(context).size.width < 800) {
              Navigator.pop(context);
            }
            context.go(route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon, 
                  color: isActive ? AppTheme.primaryBlue : (isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey), 
                  size: 21,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive 
                          ? AppTheme.primaryBlue 
                          : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
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