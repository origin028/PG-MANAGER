import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return 'R';
  }

  @override
  Widget build(BuildContext context) {
    final resident = AppData.currentResident;
    final name = resident['name']?.toString() ?? 'Resident';
    final room = resident['room_number']?.toString() ?? resident['room']?.toString() ?? '101';
    final phone = resident['phone']?.toString() ?? '9876543210';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;
    final dividerCol = isDark ? AppTheme.darkBorder : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      appBar: AppBar(
        title: Text(
          'Menu',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: textPri,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPri),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resident Mini Profile Card
                  InkWell(
                    onTap: () => context.push('/profile'),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: isDark ? AppTheme.cardShadeDarkGradient : AppTheme.heroCardGradient,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE0E7FF), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? const Color(0x1F000000) : const Color(0x144F46E5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: AppTheme.blueGradient,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x402563EB),
                                  blurRadius: 10,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _getInitials(name),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: textPri,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Room $room • +91 $phone',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: textSec,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: isDark ? AppTheme.primaryLightBlue : const Color(0xFF4F46E5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Services & Management',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textSec,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Menu Options Card
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 1. My Profile
                        _buildMenuItem(
                          context: context,
                          icon: Icons.person_outline_rounded,
                          iconColor: const Color(0xFF2563EB),
                          iconBg: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                          title: 'My Profile',
                          subtitle: 'Personal info, selfie & contact details',
                          onTap: () => context.push('/profile'),
                        ),
                        Divider(height: 1, color: dividerCol),

                        // 2. Rent & Deposit Details
                        _buildMenuItem(
                          context: context,
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: const Color(0xFF0D9488),
                          iconBg: isDark ? const Color(0xFF134E4A) : const Color(0xFFF0FDFA),
                          title: 'Rent & Deposit Details',
                          subtitle: 'Rent history, invoices & deposit status',
                          onTap: () => context.push('/rent-deposit'),
                        ),
                        Divider(height: 1, color: dividerCol),

                        // 3. Property Details
                        _buildMenuItem(
                          context: context,
                          icon: Icons.apartment_rounded,
                          iconColor: const Color(0xFF7C3AED),
                          iconBg: isDark ? const Color(0xFF4C1D95) : const Color(0xFFF5F3FF),
                          title: 'Property Details',
                          subtitle: 'Address, room, floor & house rules',
                          onTap: () => context.push('/property-details'),
                        ),
                        Divider(height: 1, color: dividerCol),

                        // 4. Raise Complaint
                        _buildMenuItem(
                          context: context,
                          icon: Icons.report_problem_outlined,
                          iconColor: const Color(0xFFEA580C),
                          iconBg: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFFF7ED),
                          title: 'Raise Complaint',
                          subtitle: 'Report maintenance, Wi-Fi or room issues',
                          onTap: () => context.push('/raise-complaint'),
                        ),
                        Divider(height: 1, color: dividerCol),

                        // 5. Call Management
                        _buildMenuItem(
                          context: context,
                          icon: Icons.headset_mic_outlined,
                          iconColor: const Color(0xFF059669),
                          iconBg: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                          title: 'Call Management',
                          subtitle: 'Contact PG manager & WhatsApp desk',
                          onTap: () => context.push('/call-management'),
                        ),
                        Divider(height: 1, color: dividerCol),

                        // 6. Settings
                        _buildMenuItem(
                          context: context,
                          icon: Icons.settings_outlined,
                          iconColor: isDark ? AppTheme.primaryLightBlue : const Color(0xFF475569),
                          iconBg: isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
                          title: 'Settings',
                          subtitle: 'Theme, language & account logout',
                          onTap: () => context.push('/settings'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.35,
                      color: textPri,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: textSec,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
