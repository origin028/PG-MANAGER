import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';

import '../../core/services/resident_api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  void _loadDashboard() async {
    try {
      final dash = await ResidentApiService.getDashboard();
      if (dash.isNotEmpty && mounted) {
        final stay = dash['stay_details'] as Map<String, dynamic>? ?? {};
        final rentDue = (dash['rent_due'] ?? 8000).toInt();
        final notices = (dash['notices'] as List?) ?? [];
        setState(() {
          AppData.currentResident = {
            ...AppData.currentResident,
            if (stay['resident_name'] != null) 'name': stay['resident_name'],
            if (stay['room_number'] != null) 'room_number': stay['room_number'],
            if (stay['room_number'] != null) 'room': stay['room_number'],
            if (stay['bed_number'] != null) 'bed': stay['bed_number'],
            if (stay['monthly_rent'] != null) 'rent': stay['monthly_rent'],
            'rent_status': rentDue == 0 ? 'Paid' : 'Unpaid',
            if (stay['property_name'] != null) 'property': stay['property_name'],
            if (stay['status'] != null) 'status': stay['status'],
          };
          if (notices.isNotEmpty) {
            AppData.notices = notices.map((n) => <String, dynamic>{
              'id': n['id']?.toString() ?? '',
              'title': n['title'] ?? 'Notice',
              'message': n['message'] ?? '',
              'date': n['created_at']?.toString().substring(0, 10) ?? '',
              'priority': n['priority'] ?? 'NORMAL',
            }).toList();
          }
        });
      }
    } catch (e) {
      debugPrint('API getDashboard error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Object? extra;
    try {
      extra = GoRouterState.of(context).extra;
    } catch (_) {
      extra = null;
    }

    Map<String, dynamic> loggedInResident = AppData.currentResident;
    if (extra is Map<String, dynamic>) {
      loggedInResident = extra;
    } else if (extra is String) {
      loggedInResident = {'name': extra, ...AppData.currentResident};
    }

    final name = (loggedInResident['name'] ?? 'Resident').toString();
    final rawRoom = loggedInResident['room_number'] ?? loggedInResident['room'];
    final roomNumber = (rawRoom != null && rawRoom.toString().trim().isNotEmpty) ? rawRoom.toString() : '101';
    final rawRent = loggedInResident['rent'];
    final int rent = (rawRent is int && rawRent > 0) ? rawRent : (int.tryParse(rawRent?.toString() ?? '') ?? 8000);
    final status = (loggedInResident['status'] ?? 'Active').toString();
    final bool isRentPaid = (loggedInResident['rent_status']?.toString().toLowerCase() == 'paid');

    final bool isPending = rawRoom == null ||
        rawRoom.toString().trim().isEmpty ||
        status.toLowerCase() == 'pending';

    // Calculate floor from room number
    String floor = '1st';
    final roomStr = roomNumber.toString();
    if (roomStr.length >= 3) {
      final floorDigit = roomStr[0];
      if (floorDigit == '1') floor = '1st';
      if (floorDigit == '2') floor = '2nd';
      if (floorDigit == '3') floor = '3rd';
      if (floorDigit == '4') floor = '4th';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ========================================================
              // HEADER ROW (Wrapped in SizedBox with full width)
              // ========================================================
              SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hey, $name',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: textPri,
                              letterSpacing: -0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Welcome to PG Pilot',
                            style: TextStyle(
                              fontSize: 13,
                              color: textSec,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cardBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => _showNotificationsModal(context),
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                          size: 22,
                        ),
                        tooltip: 'Notifications',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ========================================================
              // THE STAY CARD (DARK BLUE HERO SECTION - NO STACK)
              // ========================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E1B4B), // Deep Indigo
                      Color(0xFF312E81), // Dark Blue/Purple
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x1FFFFFFF), width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: 'YOUR STAY' & 'Living' / 'Pending' badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'YOUR STAY',
                            style: TextStyle(
                              color: Color(0xFFA5B4FC),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isPending ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isPending ? 'Pending' : 'Living',
                                style: const TextStyle(
                                  color: Color(0xFF1E1B4B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Living Since as small text above property name
                    Text(
                      'Living Since: ${isPending ? 'Pending' : '01 Oct 2026'}',
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Property name
                    const Text(
                      'BNR Luxury PG',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Room & Floor Pills
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0x26FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x3DFFFFFF)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bed_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                isPending ? 'Room Pending' : 'Room $roomNumber',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0x26FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x3DFFFFFF)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.apartment_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                isPending ? 'Floor Pending' : 'Floor $floor',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // ========================================================
              // PART 2: NOTICES BOX (BOLD, PROMINENT & SPACIOUS)
              // ========================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderCol, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        color: isDark ? AppTheme.primaryLightBlue : const Color(0xFF4F46E5),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Notices',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textPri,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '2 New',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Water maintenance tomorrow • High-Speed Wi-Fi upgrade',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: textSec,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => context.push('/notices'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View all',
                            style: TextStyle(
                              color: isDark ? AppTheme.primaryLightBlue : const Color(0xFF4F46E5),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: isDark ? AppTheme.primaryLightBlue : const Color(0xFF4F46E5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ========================================================
              // PART 3: COMPLAINT UPDATES CARD (RESOLVED COMPLAINTS)
              // ========================================================
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderCol, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => context.push('/all-complaints'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF10B981),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Complaint Updates',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: textPri,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Resolved',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Your complaint regarding "AC not cooling" has been resolved',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: textSec,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => context.push('/all-complaints'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View all',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF10B981),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 12,
                                  color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF10B981),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ========================================================
              // PART 2: DYNAMIC PAYMENT REMINDER CARD (BOLD & SPACIOUS)
              // ========================================================
              if (!isRentPaid)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF431407) : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFED7AA), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x0FF59E0B),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFEA580C),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rent Due on 05 Nov 2026',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFFED7AA) : const Color(0xFF9A3412),
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹$rent due in 6 days • Avoid late payment fee',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => context.go('/payments'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Pay Now',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: isDark ? const Color(0xFF047857) : const Color(0xFFA7F3D0), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x0F10B981),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF047857) : const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF059669),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rent Paid for this cycle - ₹$rent',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All dues cleared. Next cycle starts 01 Dec 2026.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          context.push('/receipt', extra: {
                            'invoiceId': 'INV-2026-010',
                            'amount': rent,
                            'month': 'November 2026',
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF059669),
                          side: const BorderSide(color: Color(0xFF059669), width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Receipt',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modalBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: modalBg,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.notifications_active_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Notifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPri),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF243247) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderCol),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF4C1D24) : AppTheme.softPink,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.payment_rounded, color: AppTheme.accentPink, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rent Due Reminder: November 2026',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: textPri),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Invoice: INV-2026-010 • Due 05 Nov 2026',
                                style: TextStyle(fontSize: 11.5, color: textSec),
                              ),
                            ],
                          ),
                        ),
                        Text('2h ago', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text('Amount: ', style: TextStyle(fontSize: 12, color: textSec)),
                            Text(
                              '₹ ${AppData.currentResident['rent'] ?? 8000}',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: isDark ? Colors.white : const Color(0xFF1E1B4B)),
                            ),
                          ],
                        ),
                        Builder(
                          builder: (context) {
                            final isPaid = AppData.currentResident['rent_status']?.toString().toLowerCase() == 'paid';
                            if (isPaid) {
                              return OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  context.push('/receipt', extra: {
                                    'invoiceId': 'INV-2026-010',
                                    'amount': AppData.currentResident['rent'] ?? 8000,
                                    'month': 'November 2026',
                                  });
                                },
                                icon: const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                                label: const Text('Paid (Receipt)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  side: const BorderSide(color: Color(0xFF86EFAC)),
                                  backgroundColor: const Color(0xFFF0FDF4),
                                ),
                              );
                            }
                            return ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push('/rent-payment', extra: {
                                  'id': 'INV-2026-010',
                                  'amount': AppData.currentResident['rent'] ?? 8000,
                                  'date': '05 Nov 2026',
                                  'month': 'November 2026',
                                  'autoOpen': true,
                                });
                              },
                              icon: const Icon(Icons.flash_on_rounded, size: 14),
                              label: const Text('Pay Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.verified_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 20),
                ),
                title: Text('KYC Document status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPri)),
                subtitle: Text('Your profile documents are logged with property admin.', style: TextStyle(fontSize: 12, color: textSec)),
                trailing: Text('1d ago', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
              ),
            ],
          ),
        );
      },
    );
  }
}

