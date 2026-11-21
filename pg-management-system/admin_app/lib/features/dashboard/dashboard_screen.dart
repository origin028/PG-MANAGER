import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/widgets/app_dropdown.dart';

import '../../core/services/admin_api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 1. The current selected property synced with global AppData
  String get _selectedProperty => _propertyData.containsKey(AppData.selectedProperty) ? AppData.selectedProperty : 'BNR Luxury PG';

  Map<String, dynamic> _dashboardStats = {};
  Map<String, dynamic> _bedCapacity = {};

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_onPropertyChange);
    AppData.loadResidentsFromStorage().then((_) {
      if (mounted) setState(() {});
    });
    _loadDashboardData();
  }

  @override
  void dispose() {
    AppData.selectedPropertyIdNotifier.removeListener(_onPropertyChange);
    super.dispose();
  }

  void _onPropertyChange() {
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;

    final propId = AppData.selectedPropertyId;
    Map<String, dynamic> stats = {};
    try {
      stats = await AdminApiService.getDashboardMetrics(propertyId: propId);
    } catch (e) {
      debugPrint('Dashboard metrics fetch info: $e');
    }

    List<Map<String, dynamic>> residents = [];
    try {
      residents = await AdminApiService.getResidents(propertyId: propId);
    } catch (e) {
      debugPrint('Residents fetch info: $e');
    }

    Map<String, dynamic> bedCapacity = {};
    try {
      bedCapacity = await AdminApiService.getBedCapacity();
    } catch (_) {}

    List<Map<String, dynamic>>? pendingList;
    try {
      // Query pending approvals across all accessible properties of the administrator
      pendingList = await AdminApiService.getPendingResidentApprovals();
    } catch (_) {
      try {
        pendingList = await AdminApiService.getPendingResidentApprovals(propertyId: propId);
      } catch (err) {
        debugPrint('Pending approvals fetch info: $err');
      }
    }

    if (mounted) {
      if (pendingList != null) {
        AppData.pendingResidents = pendingList.map((p) => <String, dynamic>{
          'id': p['resident_id']?.toString() ?? p['id']?.toString() ?? '',
          'name': p['full_name'] ?? p['name'] ?? '',
          'phone': p['phone'] ?? '',
          'email': p['email'] ?? '',
          'status': 'Pending Approval',
          'property_id': p['property_id']?.toString() ?? '',
          'property_name': p['property_name'] ?? '',
          'raw': p,
        }).toList();
      }
      setState(() {
        _dashboardStats = stats;
        _bedCapacity = bedCapacity;
        if (residents.isNotEmpty) {
          AppData.residents = residents.map((r) => <String, dynamic>{
            'name': r['full_name'] ?? r['name'] ?? 'Resident',
            'phone': r['phone'] ?? '',
            'email': r['email'] ?? '',
            'room': r['room_number'] ?? '101',
            'bed': r['bed_number'] ?? 'Bed A',
            'rent': (r['monthly_rent'] ?? 8000).toInt(),
            'deposit': (r['security_deposit'] ?? 10000).toInt(),
            'status': (r['status'] == 'ACTIVE' || r['status'] == 'Active') ? 'Paid' : 'Unpaid',
            'dueDate': '05 Nov 2026',
            'id': r['id']?.toString() ?? '',
          }).toList();
        }
      });
    }
  }

  // 2. Mock data for each property
  final Map<String, Map<String, dynamic>> _propertyData = {
    'BNR Luxury PG': {
      'unpaid': '14',
      'totalTenants': '150',
      'availableBeds': '3',
      'revenue': '₹ 1,42,220',
      'growth': '+3.4%',
    },
    'Skyline Girls PG': {
      'unpaid': '5',
      'totalTenants': '85',
      'availableBeds': '25',
      'revenue': '₹ 85,000',
      'growth': '+1.2%',
    },
    'Green Nest PG': {
      'unpaid': '0',
      'totalTenants': '60',
      'availableBeds': '4',
      'revenue': '₹ 72,000',
      'growth': '-2.1%',
    },
  };

  // Room Availability Modal showing 2-column grid of rooms with vacant beds and floor numbers
  void _showRoomAvailabilityModal(BuildContext context) {
    final availableRooms = AppData.rooms.where((room) {
      final beds = (room['beds'] as List?) ?? [];
      return beds.any((bed) => bed['status'] == 'Available');
    }).toList();

    showPremiumDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final itemBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
        final itemBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final textPri = isDark ? Colors.white : AppTheme.textDark;
        final textSec = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;

        return PremiumDialog(
          maxWidth: 680,
          title: 'Room Availability',
          subtitle: 'Live vacant bed count across properties',
          icon: Icons.bedroom_parent_rounded,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Close', style: TextStyle(color: textSec)),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (availableRooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No rooms with vacant beds currently available.',
                      style: TextStyle(color: AppTheme.textGrey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: availableRooms.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 2.4,
                  ),
                  itemBuilder: (_, index) {
                    final room = availableRooms[index];
                    final beds = (room['beds'] as List?) ?? [];
                    final vacantBeds = beds.where((b) => b['status'] == 'Available').length;
                    final roomNumber = room['number'] ?? '';
                    final floorName = room['floor'] ?? 'Ground Floor';
                    final roomType = room['type'] ?? 'Standard';

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(dialogCtx);
                          AppData.selectedRoomForHighlight = roomNumber;
                          context.go('/rooms?room=$roomNumber');
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: itemBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: itemBorder),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Room $roomNumber',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: textPri,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: Text(
                                      '$vacantBeds ${vacantBeds == 1 ? 'Bed' : 'Beds'}',
                                      style: const TextStyle(
                                        color: AppTheme.statusOk,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      floorName,
                                      style: TextStyle(fontSize: 12, color: textSec),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    roomType,
                                    style: TextStyle(fontSize: 12, color: textSec),
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
            ],
          ),
        );
      },
    );
  }

  // Format payment due date helper (e.g. '05 Nov 2026')
  String _formatDueDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    return '$day $month ${dt.year}';
  }

  void _showKycDocumentPreview(BuildContext context, String residentId, String docType, String docLabel) {
    showPremiumDialog(
      context: context,
      builder: (ctx) => FutureBuilder<Uint8List?>(
        future: AdminApiService.getKycDocumentBytes(residentId, docType),
        builder: (ctx, snapshot) {
          return PremiumDialog(
            maxWidth: 540,
            title: docLabel,
            subtitle: 'Identity & Document Verification',
            icon: Icons.verified_user_rounded,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
              ),
            ],
            child: Builder(
              builder: (_) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primaryTeal),
                          SizedBox(height: 14),
                          Text('Loading secured KYC document...', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }
                if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined, color: AppTheme.textGrey, size: 48),
                          SizedBox(height: 10),
                          Text(
                            'Document could not be loaded or is unavailable.',
                            style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showPendingApprovalsListDialog(BuildContext context) {
    showPremiumDialog(
      context: context,
      builder: (ctx) => PremiumDialog(
        maxWidth: 580,
        title: 'Pending Registrations (${AppData.pendingResidents.length})',
        subtitle: 'Applicants awaiting room allocation & check-in approval',
        icon: Icons.pending_actions_rounded,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
          ),
        ],
        child: AppData.pendingResidents.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: Text('No pending resident registrations.', style: TextStyle(color: AppTheme.textGrey)),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: AppData.pendingResidents.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final res = AppData.pendingResidents[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.lightTeal,
                          child: Text(
                            res['name']?.toString().isNotEmpty == true
                                ? res['name'].toString()[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                res['name'] ?? 'Pending Resident',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
                              ),
                              const SizedBox(height: 2),
                              Text('+91 ${res['phone'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                              if (res['property_name']?.toString().isNotEmpty == true)
                                Text(
                                  res['property_name'],
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.primaryTeal, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAssignRoomAndRentDialog(context, res);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  // Open responsive 'Assign Room & Rent' Dialog
  void _showAssignRoomAndRentDialog(BuildContext context, Map<String, dynamic> resident) {
    final messenger = ScaffoldMessenger.of(context);
    final raw = (resident['raw'] as Map?) ?? {};
    final resId = resident['id']?.toString() ?? raw['id']?.toString() ?? '';
    final resName = resident['name']?.toString() ?? raw['full_name']?.toString() ?? 'Pending Resident';
    final resPhone = resident['phone']?.toString() ?? raw['phone']?.toString() ?? '';
    final resEmail = resident['email']?.toString() ?? raw['email']?.toString() ?? '';
    final propName = resident['property_name']?.toString() ?? raw['property_name']?.toString() ?? '';

    // Build room options from AppData.rooms
    final List<Map<String, dynamic>> roomList = AppData.rooms;
    String initialRoom = '101';
    for (var r in roomList) {
      final beds = (r['beds'] as List?) ?? [];
      if (beds.any((b) => b['status'] == 'Available')) {
        initialRoom = r['number'].toString().trim();
        break;
      }
    }
    if (roomList.isNotEmpty && !roomList.any((r) => r['number'].toString().trim() == initialRoom)) {
      initialRoom = roomList.first['number'].toString().trim();
    }

    String selectedRoom = initialRoom;
    final roomController = TextEditingController(text: initialRoom);

    // Helper to get available beds for a given room number
    List<String> getAvailableBedsForRoom(String rNum) {
      final rm = roomList.firstWhere(
        (r) => r['number'].toString().trim() == rNum.trim(),
        orElse: () => <String, dynamic>{},
      );
      final beds = (rm['beds'] as List?) ?? [];
      final avail = beds
          .where((b) => b['status'] == 'Available')
          .map((b) => b['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      if (avail.isEmpty) {
        return ['Bed A (Auto-assign)', 'Bed B'];
      }
      return avail;
    }

    List<String> currentAvailableBeds = getAvailableBedsForRoom(selectedRoom);
    String selectedBed = currentAvailableBeds.isNotEmpty ? currentAvailableBeds.first : 'Bed A';

    final rentController = TextEditingController(text: '8000');
    final now = DateTime.now();
    DateTime selectedDueDate = DateTime(now.year, now.month + 1, 5);
    final dueDateController = TextEditingController(text: _formatDueDate(selectedDueDate));

    bool isRentEditable = false;
    String? validationError;
    bool isSubmitting = false;

    // Build list of room number choices
    final roomOptions = roomList.isNotEmpty
        ? roomList.map((r) => r['number'].toString().trim()).toSet().toList()
        : <String>['101', '102', '103', '201', '202'];
    if (!roomOptions.contains(selectedRoom)) {
      roomOptions.insert(0, selectedRoom);
    }

    // KYC document definitions
    final kycDocs = <Map<String, dynamic>>[
      {
        'type': 'aadhaar_front',
        'title': 'Aadhaar Card Front',
        'shortTitle': 'Aadhaar Front',
        'icon': Icons.badge_outlined,
        'path': raw['aadhaar_front_path'],
      },
      {
        'type': 'aadhaar_back',
        'title': 'Aadhaar Card Back',
        'shortTitle': 'Aadhaar Back',
        'icon': Icons.badge_outlined,
        'path': raw['aadhaar_back_path'],
      },
      {
        'type': 'pan_card',
        'title': 'PAN Card',
        'shortTitle': 'PAN Card',
        'icon': Icons.credit_card_outlined,
        'path': raw['pan_card_path'],
      },
      {
        'type': 'resident_selfie',
        'title': 'Resident Selfie',
        'shortTitle': 'Selfie Photo',
        'icon': Icons.face_outlined,
        'path': raw['resident_selfie_path'],
      },
      if (raw['passport_path'] != null)
        {
          'type': 'passport',
          'title': 'Passport',
          'shortTitle': 'Passport',
          'icon': Icons.menu_book_outlined,
          'path': raw['passport_path'],
        },
    ];

    showPremiumDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogContentCtx, setDialogState) {
          final mediaQuery = MediaQuery.of(dialogCtx);
          final screenWidth = mediaQuery.size.width;
          final screenHeight = mediaQuery.size.height;
          final isDesktop = screenWidth >= 820;
          final isSmallMobile = screenWidth < 460;

          final dialogMaxWidth = isDesktop
              ? 920.0
              : math.min(screenWidth * 0.94, 680.0);
          final dialogMaxHeight = (screenHeight * 0.90).clamp(380.0, 780.0);

          // Sub-widget: KYC Document Thumbnail Card
          Widget buildKycCard(Map<String, dynamic> doc) {
            final hasDoc = resId.isNotEmpty && doc['path'] != null && doc['path'].toString().isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(doc['icon'] as IconData, size: 15, color: hasDoc ? AppTheme.primaryBlue : AppTheme.textGrey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          doc['shortTitle'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasDoc ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          hasDoc ? 'Uploaded' : 'Missing',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: hasDoc ? AppTheme.successGreen : AppTheme.textGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!hasDoc)
                    Container(
                      height: 72,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: const Center(
                        child: Text('Not provided', style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => _showKycDocumentPreview(context, resId, doc['type'] as String, doc['title'] as String),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 72,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<Uint8List?>(
                              future: AdminApiService.getKycDocumentBytes(resId, doc['type'] as String),
                              builder: (ctx, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                                  return const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image_outlined, size: 20, color: Colors.grey),
                                        SizedBox(height: 2),
                                        Text('Tap to inspect', style: TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                                      ],
                                    ),
                                  );
                                }
                                return Image.memory(snap.data!, fit: BoxFit.cover);
                              },
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in, color: Colors.white, size: 12),
                                    SizedBox(width: 3),
                                    Text('Enlarge', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }

          // Section 1: Resident Information & Profile
          Widget buildResidentInfo() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                            child: Text(
                              resName.isNotEmpty ? resName[0].toUpperCase() : 'R',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  resName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  resPhone.isNotEmpty ? '+91 $resPhone' : '',
                                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (resEmail.isNotEmpty || propName.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        if (resEmail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.email_outlined, size: 14, color: AppTheme.textGrey),
                                const SizedBox(width: 6),
                                Expanded(child: Text(resEmail, style: const TextStyle(fontSize: 12, color: AppTheme.textDark))),
                              ],
                            ),
                          ),
                        if (propName.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.business_outlined, size: 14, color: AppTheme.primaryBlue),
                              const SizedBox(width: 6),
                              Expanded(child: Text('Property: $propName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue))),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                if (raw['date_of_birth'] != null || raw['gender'] != null || raw['occupation'] != null || raw['city'] != null || raw['emergency_contact'] != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Applicant Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            if (raw['date_of_birth'] != null)
                              Text('DOB: ${raw['date_of_birth']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
                            if (raw['gender'] != null)
                              Text('Gender: ${raw['gender']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
                            if (raw['occupation'] != null)
                              Text('Occupation: ${raw['occupation']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
                            if (raw['emergency_contact'] != null)
                              Text('Emergency: ${raw['emergency_contact']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
                          ],
                        ),
                        if (raw['city'] != null || raw['state'] != null || raw['pincode'] != null || raw['house_flat_no'] != null || raw['street'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Address: ${[raw['house_flat_no'], raw['street'], raw['city'], raw['state'], raw['pincode']].where((e) => e != null && e.toString().trim().isNotEmpty).join(', ')}',
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          }

          // Section 2: KYC Documents Verification
          Widget buildKycSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'KYC Documents Verification',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Review applicant identity proof & photographs:', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final maxW = constraints.maxWidth;
                    final cardWidth = isDesktop
                        ? 180.0
                        : (maxW < 330 ? maxW : ((maxW - 10) / 2).clamp(130.0, 260.0));
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kycDocs.map((doc) {
                        return SizedBox(width: cardWidth, child: buildKycCard(doc));
                      }).toList(),
                    );
                  },
                ),
              ],
            );
          }

          // Section 3: Room & Bed Allocation
          Widget buildRoomAllocation() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.meeting_room_outlined, size: 18, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Room & Bed Allocation',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Room Number Dropdown
                const Text('Room Number *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: roomOptions.contains(selectedRoom) ? selectedRoom : roomOptions.first,
                  decoration: InputDecoration(
                    hintText: 'Select Room',
                    prefixIcon: const Icon(Icons.meeting_room_outlined, color: AppTheme.primaryBlue),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: roomOptions.map((rNum) {
                    final rm = roomList.firstWhere(
                      (r) => r['number'].toString().trim() == rNum,
                      orElse: () => <String, dynamic>{},
                    );
                    final floor = rm['floor']?.toString() ?? '';
                    final label = floor.isNotEmpty ? 'Room $rNum ($floor)' : 'Room $rNum';
                    return DropdownMenuItem<String>(
                      value: rNum,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedRoom = val;
                        roomController.text = val;
                        currentAvailableBeds = getAvailableBedsForRoom(val);
                        selectedBed = currentAvailableBeds.isNotEmpty ? currentAvailableBeds.first : 'Bed A';
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Available Bed Dropdown
                const Text('Available Bed *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: currentAvailableBeds.contains(selectedBed)
                      ? selectedBed
                      : (currentAvailableBeds.isNotEmpty ? currentAvailableBeds.first : null),
                  decoration: InputDecoration(
                    hintText: 'Select Bed',
                    prefixIcon: const Icon(Icons.bed_outlined, color: AppTheme.primaryBlue),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: currentAvailableBeds.map((bedName) {
                    return DropdownMenuItem<String>(
                      value: bedName,
                      child: Text(
                        bedName,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedBed = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Monthly Rent TextField
                const Text('Monthly Rent (₹) *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                const SizedBox(height: 6),
                TextField(
                  controller: rentController,
                  keyboardType: TextInputType.number,
                  readOnly: !isRentEditable,
                  decoration: InputDecoration(
                    hintText: '8000',
                    prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppTheme.primaryBlue),
                    filled: true,
                    fillColor: isRentEditable ? Colors.white : const Color(0xFFF1F5F9),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isRentEditable ? Icons.lock_open_rounded : Icons.edit,
                        color: isRentEditable ? AppTheme.successGreen : AppTheme.primaryBlue,
                      ),
                      tooltip: isRentEditable ? 'Rent field is editable' : 'Click to edit rent',
                      onPressed: () {
                        setDialogState(() {
                          isRentEditable = !isRentEditable;
                        });
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: isRentEditable
                        ? 'Unlocked: Custom rent enabled'
                        : 'Locked: Tap edit icon to change rent',
                  ),
                ),
                const SizedBox(height: 14),

                // Payment Due Date TextField
                const Text('Payment Due Date *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                const SizedBox(height: 6),
                TextField(
                  controller: dueDateController,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogCtx,
                      initialDate: selectedDueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDueDate = picked;
                        dueDateController.text = _formatDueDate(picked);
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Select Due Date',
                    prefixIcon: const Icon(Icons.event_note_rounded, color: AppTheme.primaryBlue),
                    suffixIcon: const Icon(Icons.calendar_month_rounded, color: AppTheme.primaryBlue),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: 'Tap to select monthly due date',
                  ),
                ),
              ],
            );
          }

          // Handle Rejection
          void onReject() {
            final reasonController = TextEditingController();
            String? rejectError;
            bool isRejectSubmitting = false;

            showPremiumDialog(
              context: context,
              builder: (rejectCtx) => StatefulBuilder(
                builder: (rCtx, setRejectState) => PremiumDialog(
                  maxWidth: 460,
                  title: 'Reject Registration',
                  subtitle: resName,
                  icon: Icons.cancel_outlined,
                  actions: [
                    TextButton(
                      onPressed: isRejectSubmitting ? null : () => Navigator.pop(rejectCtx),
                      child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                    ),
                    ElevatedButton.icon(
                      onPressed: isRejectSubmitting ? null : () async {
                        final reason = reasonController.text.trim();
                        if (reason.isEmpty) {
                          setRejectState(() => rejectError = 'Please enter a valid rejection reason.');
                          return;
                        }
                        setRejectState(() {
                          isRejectSubmitting = true;
                          rejectError = null;
                        });

                        if (resId.isNotEmpty) {
                          try {
                            await AdminApiService.rejectResident(resId, reason: reason);
                          } catch (e) {
                            setRejectState(() {
                              isRejectSubmitting = false;
                              rejectError = 'Rejection failed: $e';
                            });
                            return;
                          }
                        }
                        AppData.pendingResidents.removeWhere((p) => p['name'] == resName || p['id'] == resId);
                        AppData.saveResidentsToStorage();

                        if (rejectCtx.mounted) Navigator.pop(rejectCtx);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        setState(() {});
                        _loadDashboardData();

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Registration for $resName was rejected. Notification sent.'),
                            backgroundColor: AppTheme.statusRed,
                          ),
                        );
                      },
                      icon: isRejectSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cancel_outlined, size: 18),
                      label: Text(isRejectSubmitting ? 'Rejecting...' : 'Confirm Rejection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.statusRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PremiumDialogBanner(
                        message: 'Rejecting this applicant will cancel the registration and send an explanatory notification to their registered mobile number.',
                        type: BannerType.warning,
                      ),
                      const SizedBox(height: 16),
                      PremiumFormField(
                        controller: reasonController,
                        label: 'Rejection Reason',
                        hintText: 'e.g. Incomplete KYC documents or invalid identity proof',
                        maxLines: 3,
                        isRequired: true,
                        errorMessage: rejectError,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Handle Approval
          void onConfirmAndAssign() async {
            final roomNo = selectedRoom.trim();
            final rentText = rentController.text.trim();
            final dueDate = dueDateController.text.trim();

            if (roomNo.isEmpty) {
              setDialogState(() => validationError = 'Please enter a room number.');
              return;
            }
            final rentVal = int.tryParse(rentText);
            if (rentVal == null || rentVal <= 0) {
              setDialogState(() => validationError = 'Please enter a valid monthly rent amount.');
              return;
            }

            setDialogState(() {
              isSubmitting = true;
              validationError = null;
            });

            if (resId.isNotEmpty) {
              try {
                await AdminApiService.approveResident(
                  resId,
                  monthlyRent: rentVal.toDouble(),
                );
              } catch (e) {
                setDialogState(() {
                  isSubmitting = false;
                  validationError = 'Approval failed: $e';
                });
                return;
              }
            }

            final err = AppData.assignResidentToRoom(
              roomNo,
              resName,
              phone: resPhone,
              rent: rentVal,
              dueDate: dueDate,
            );

            if (err != null && resId.isEmpty) {
              setDialogState(() {
                isSubmitting = false;
                validationError = err;
              });
              return;
            }

            // Ensure removed from pendingResidents
            AppData.pendingResidents.removeWhere((p) => p['name'] == resName || p['id'] == resId);
            AppData.saveResidentsToStorage();

            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            setState(() {});
            _loadDashboardData();

            messenger.showSnackBar(
              SnackBar(
                content: Text('$resName assigned to Room $roomNo! Monthly Rent: ₹$rentVal, Due Date: $dueDate'),
                backgroundColor: AppTheme.successGreen,
                duration: const Duration(seconds: 4),
              ),
            );
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: EdgeInsets.symmetric(
              horizontal: isSmallMobile ? 10 : 20,
              vertical: isSmallMobile ? 12 : 20,
            ),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogMaxWidth,
                maxHeight: dialogMaxHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- 1. STICKY HEADER ---
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallMobile ? 14 : 20,
                      vertical: isSmallMobile ? 12 : 16,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.meeting_room_rounded, color: AppTheme.primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Assign Room & Rent',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Text(
                            resident['status'] ?? 'Pending Approval',
                            style: const TextStyle(color: Color(0xFFB45309), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.textGrey, size: 20),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                  ),

                  // --- 2. SCROLLABLE BODY ---
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isSmallMobile ? 14 : 20),
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // LEFT COLUMN: Resident Info & Profile + Room & Bed Allocation
                                Expanded(
                                  flex: 11,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      buildResidentInfo(),
                                      const SizedBox(height: 20),
                                      buildRoomAllocation(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // RIGHT COLUMN: KYC Documents Verification
                                Expanded(
                                  flex: 10,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      buildKycSection(),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                buildResidentInfo(),
                                const SizedBox(height: 18),
                                buildKycSection(),
                                const SizedBox(height: 18),
                                buildRoomAllocation(),
                              ],
                            ),
                    ),
                  ),

                  // --- 3. STICKY ACTION FOOTER ---
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallMobile ? 12 : 20,
                      vertical: isSmallMobile ? 10 : 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (validationError != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFF87171)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    validationError!,
                                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        LayoutBuilder(
                          builder: (context, footerConstraints) {
                            final footerWidth = footerConstraints.maxWidth;
                            if (footerWidth < 680) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    onPressed: isSubmitting ? null : onConfirmAndAssign,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: isSubmitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_circle_outline, size: 18),
                                              SizedBox(width: 6),
                                              Text('Confirm & Assign', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: isSubmitting ? null : onReject,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            side: const BorderSide(color: Colors.red),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: const Text('Reject Application', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextButton(
                                          onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                                          child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                TextButton(
                                  onPressed: isSubmitting ? null : onReject,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                      SizedBox(width: 6),
                                      Text('Reject Application', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: isSubmitting ? null : onConfirmAndAssign,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle_outline, size: 18),
                                            SizedBox(width: 6),
                                            Text('Confirm & Assign', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentData = _propertyData[_selectedProperty]!;

    // Calculate real available beds from AppData
    int realAvailableBeds = 0;
    for (var room in AppData.rooms) {
      for (var bed in room['beds']) {
        if (bed['status'] == 'Available') realAvailableBeds++;
      }
    }

    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: AppTheme.primaryBlue,
            child: CustomScrollView(
            slivers: [
              // Main Content starting cleanly below global header without overlaps
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16.0 : 24.0,
                  isMobile ? 16.0 : 24.0,
                  isMobile ? 16.0 : 24.0,
                  32.0,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                      // 1. Compact Dashboard Header (Operations Dashboard with Send Reminder)
                      _buildDashboardHeader(context),
                      const SizedBox(height: 20),

                      // 2. Pending Removal & Resident Approval Section (Repositioned directly below Operations Dashboard)
                      if (AppData.pendingResidents.isNotEmpty) ...[
                        PendingApprovalsCard(
                          pendingResidents: AppData.pendingResidents,
                          onReviewAndAssign: () {
                            if (AppData.pendingResidents.length == 1) {
                              _showAssignRoomAndRentDialog(
                                context,
                                AppData.pendingResidents.first,
                              );
                            } else {
                              _showPendingApprovalsListDialog(context);
                            }
                          },
                          onReject: () {
                            if (AppData.pendingResidents.isNotEmpty) {
                              _showRejectApplicationDirectDialog(
                                context,
                                AppData.pendingResidents.first,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                      ] else ...[
                        _buildNoPendingApprovalsCard(context),
                        const SizedBox(height: 20),
                      ],

                      // 3. Important Dashboard Statistics: Bed Capacity Card
                      _buildBedCapacityCard(context),
                      const SizedBox(height: 20),

                      // 4. Important Dashboard Statistics: Stat Cards Row
                      _buildStatCardsRow(context, currentData, realAvailableBeds),
                      const SizedBox(height: 24),

                      // 5. Main Residents Directory Table
                      _buildResidentsTable(context),
                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Bed Capacity Card Widget (Strictly Fixed 240 Beds Limit)
  Widget _buildBedCapacityCard(BuildContext context) {
    final totalCapacity = (_bedCapacity['total_capacity'] as num?)?.toInt() ?? 240;
    final usedBeds = (_bedCapacity['used_beds'] as num?)?.toInt() ?? 0;
    final remainingBeds = (_bedCapacity['remaining_beds'] as num?)?.toInt() ?? (totalCapacity - usedBeds);
    final usagePct = (_bedCapacity['usage_percentage'] as num?)?.toDouble() ??
        (totalCapacity > 0 ? (usedBeds / totalCapacity * 100) : 0.0);
    final isWarning = _bedCapacity['is_warning_threshold'] == true || (totalCapacity > 0 && (usedBeds / totalCapacity) >= 0.9);
    final isCapacityReached = _bedCapacity['is_capacity_reached'] == true || usedBeds >= totalCapacity;

    final progressVal = totalCapacity > 0 ? (usedBeds / totalCapacity).clamp(0.0, 1.0) : 0.0;
    final barColor = isCapacityReached
        ? AppTheme.logoutRed
        : (isWarning ? const Color(0xFFF59E0B) : AppTheme.primaryBlue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCapacityReached
              ? AppTheme.logoutRed.withValues(alpha: 0.5)
              : (isWarning ? const Color(0xFFF59E0B).withValues(alpha: 0.5) : AppTheme.inputBorder),
          width: (isCapacityReached || isWarning) ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.hotel_rounded, color: barColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Organization Bed Capacity',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '240 Beds Max Limit',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textGrey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.scaffoldBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.inputBorder),
                ),
                child: Text(
                  'Fixed: $totalCapacity Beds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Capacity-reached or Warning banner
          if (isCapacityReached) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_rounded, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your organization has reached its maximum bed capacity of 240. Please contact Origin for assistance.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (isWarning) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Warning: Bed capacity usage is at ${usagePct.toStringAsFixed(1)}% ($usedBeds of $totalCapacity beds used). Approaching maximum capacity of 240.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressVal,
              minHeight: 10,
              backgroundColor: AppTheme.inputBorder.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 16),

          // 4 Stats in row / grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 600;
              final items = [
                _buildCapacityStatItem('Total Capacity', '$totalCapacity Beds', AppTheme.primaryBlue),
                _buildCapacityStatItem('Used Beds', '$usedBeds Beds', barColor),
                _buildCapacityStatItem('Remaining Beds', '$remainingBeds Beds', AppTheme.successGreen),
                _buildCapacityStatItem('Usage', '${usagePct.toStringAsFixed(1)}%', barColor),
              ];
              if (isSmall) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: items[0]),
                        const SizedBox(width: 8),
                        Expanded(child: items[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: items[2]),
                        const SizedBox(width: 8),
                        Expanded(child: items[3]),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: items.map((w) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: w,
                ))).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textGrey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showRejectApplicationDirectDialog(BuildContext context, Map<String, dynamic> resident) {
    final resId = resident['id']?.toString() ?? '';
    final resName = resident['name'] ?? resident['full_name'] ?? 'Applicant';
    final reasonController = TextEditingController();
    String? rejectError;
    bool isRejectSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (rejectCtx) => StatefulBuilder(
        builder: (rCtx, setRejectState) => PremiumDialog(
          maxWidth: 440,
          title: 'Reject Registration',
          subtitle: 'Cancel applicant registration and state rejection reason',
          icon: Icons.cancel_outlined,
          actions: [
            OutlinedButton(
              onPressed: isRejectSubmitting ? null : () => Navigator.pop(rejectCtx),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: isRejectSubmitting
                  ? null
                  : () async {
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) {
                        setRejectState(() => rejectError = 'Please enter a valid rejection reason.');
                        return;
                      }
                      setRejectState(() {
                        isRejectSubmitting = true;
                        rejectError = null;
                      });
                      try {
                        if (resId.isNotEmpty && !resId.startsWith('p')) {
                          await AdminApiService.rejectResident(resId, reason: reason);
                        }
                      } catch (e) {
                        debugPrint('API rejectResident error: $e');
                      }
                      setState(() {
                        AppData.pendingResidents.removeWhere((r) => r['id'] == resId);
                      });
                      if (rejectCtx.mounted) Navigator.pop(rejectCtx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Registration for $resName was rejected.'),
                            backgroundColor: AppTheme.statusRed,
                          ),
                        );
                      }
                    },
              icon: isRejectSubmitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cancel_outlined, size: 16),
              label: Text(isRejectSubmitting ? 'Rejecting...' : 'Confirm Rejection'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusRed, foregroundColor: Colors.white),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Applicant: $resName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              PremiumFormField(
                label: 'Rejection Reason',
                isRequired: true,
                controller: reasonController,
                hintText: 'e.g., Incomplete KYC documents or no vacant bed matching criteria',
                maxLines: 2,
                errorMessage: rejectError,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReminderDialog(
    BuildContext context, {
    String? targetResidentName,
    String? targetResidentId,
    String? defaultAmount,
  }) {
    bool isSubmitting = false;
    String selectedMode = 'SMS & WhatsApp Notification';
    final customMsgCtrl = TextEditingController(
      text: targetResidentName != null
          ? 'Dear $targetResidentName, gentle reminder to clear your pending rent of ₹ ${defaultAmount ?? '8,500'} for this cycle. Thank you!'
          : 'Dear Resident, this is a friendly reminder to clear your monthly rent dues. Please ignore if already paid.',
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showPremiumDialog(
      context: context,
      builder: (dContext) => StatefulBuilder(
        builder: (ctx, setDState) => PremiumDialog(
          maxWidth: 480,
          title: targetResidentName != null ? 'Send Rent Reminder' : 'Broadcast Rent Reminders',
          subtitle: targetResidentName != null
              ? 'Send automated payment reminder to $targetResidentName'
              : 'Dispatch payment reminder notification to all residents with pending dues',
          icon: Icons.notifications_active_outlined,
          actions: [
            OutlinedButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dContext),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setDState(() => isSubmitting = true);
                      await Future.delayed(const Duration(milliseconds: 500));
                      if (dContext.mounted) Navigator.pop(dContext);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  targetResidentName != null
                                      ? 'Payment reminder sent to $targetResidentName!'
                                      : 'Rent reminders dispatched to all pending residents!',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            backgroundColor: AppTheme.successGreen,
                          ),
                        );
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                isSubmitting ? 'Sending...' : 'Send Reminder',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notification Channel',
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              AppDropdown.simple(
                height: 40,
                value: selectedMode,
                items: const [
                  'SMS & WhatsApp Notification',
                  'In-App Push Notification',
                  'Email Statement Reminder',
                ],
                onChanged: (val) => setDState(() => selectedMode = val),
              ),
              const SizedBox(height: 14),
              PremiumFormField(
                label: 'Reminder Message',
                isRequired: true,
                controller: customMsgCtrl,
                hintText: 'Enter reminder message',
                maxLines: 3,
                prefixIcon: const Icon(Icons.message_outlined, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 1. Compact Dashboard Header (No "Welcome, Property Manager", No "Monitor Residents")
  Widget _buildDashboardHeader(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardBackgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 520;

          final titleSection = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.lightTealDark : AppTheme.lightTeal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: AppTheme.primaryTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Operations Dashboard',
                      style: GoogleFonts.manrope(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppTheme.successGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$_selectedProperty • Real-Time Synchronization',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final reminderButton = ElevatedButton.icon(
            onPressed: () => _showReminderDialog(context),
            icon: const Icon(Icons.notifications_active_outlined, size: 15),
            label: Text(
              'Send Reminder',
              style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleSection,
                const SizedBox(height: 12),
                reminderButton,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleSection),
              const SizedBox(width: 12),
              reminderButton,
            ],
          );
        },
      ),
    );
  }

  // 2. Stat Cards Row (Rent Overview & Room Availability)
  Widget _buildStatCardsRow(BuildContext context, Map<String, dynamic> currentData, int realAvailableBeds) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;
        if (isMobile) {
          return Column(
            children: [
              _buildStatCard(
                title: 'Rent Overview',
                subtitle: 'Tenants Unpaid',
                value: _dashboardStats.isNotEmpty
                    ? '${_dashboardStats['total_residents'] ?? 0} / ${_dashboardStats['pending_rent'] ?? 0}'
                    : '${currentData['totalTenants']} / ${currentData['unpaid']}',
                icon: Icons.account_balance_wallet_rounded,
                iconColor: AppTheme.primaryTeal,
                valueColor: AppTheme.primaryTeal,
                isOutlinedButton: false,
                onTap: () => context.go('/payments'),
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                title: 'Room Availability',
                subtitle: 'Beds Available',
                value: _dashboardStats.isNotEmpty && _dashboardStats['vacant_beds'] != null
                    ? _dashboardStats['vacant_beds'].toString()
                    : realAvailableBeds.toString(),
                icon: Icons.bedroom_parent_rounded,
                iconColor: AppTheme.successGreen,
                valueColor: AppTheme.successGreen,
                isOutlinedButton: true,
                onTap: () => _showRoomAvailabilityModal(context),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Rent Overview',
                subtitle: 'Tenants Unpaid',
                value: _dashboardStats.isNotEmpty
                    ? '${_dashboardStats['total_residents'] ?? 0} / ${_dashboardStats['pending_rent'] ?? 0}'
                    : '${currentData['totalTenants']} / ${currentData['unpaid']}',
                icon: Icons.account_balance_wallet_rounded,
                iconColor: AppTheme.primaryTeal,
                valueColor: AppTheme.primaryTeal,
                isOutlinedButton: false,
                onTap: () => context.go('/payments'),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatCard(
                title: 'Room Availability',
                subtitle: 'Beds Available',
                value: _dashboardStats.isNotEmpty && _dashboardStats['vacant_beds'] != null
                    ? _dashboardStats['vacant_beds'].toString()
                    : realAvailableBeds.toString(),
                icon: Icons.bedroom_parent_rounded,
                iconColor: AppTheme.successGreen,
                valueColor: AppTheme.successGreen,
                isOutlinedButton: true,
                onTap: () => _showRoomAvailabilityModal(context),
              ),
            ),
          ],
        );
      },
    );
  }

  // Attractive Empty State when there are no pending removal/approval requests
  Widget _buildNoPendingApprovalsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardBackgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.successGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppTheme.successGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No Pending Removal or Onboarding Requests',
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'All resident stays, clearances, and room allocations are up to date.',
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'All Clear',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.successGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResidentsTable(BuildContext context) {
    final residentsList = AppData.residents;

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final isCompact = cardConstraints.maxWidth < 700;
        final isNarrowHeader = cardConstraints.maxWidth < 560;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNarrowHeader)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.people_alt_rounded, color: AppTheme.primaryBlue, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Residents Directory',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${residentsList.where((r) => r['status'] == 'Active').length} active residents allocated',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.go('/residents'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('View Full Table', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.people_alt_rounded, color: AppTheme.primaryBlue, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Residents Directory',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${residentsList.where((r) => r['status'] == 'Active').length} active residents allocated',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => context.go('/residents'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('View Full Table', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                if (residentsList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No residents found.', style: TextStyle(color: AppTheme.textGrey)),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: residentsList.length > 5 ? 5 : residentsList.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 18, color: Color(0xFFF8FAFC)),
                    itemBuilder: (ctx, index) {
                      final res = residentsList[index];
                      final isPending = res['status'] == 'Pending' || res['room'] == null || res['room_number'] == null;
                      final roomStr = (res['room_number'] ?? res['room'])?.toString();
                      final bedStr = res['bed']?.toString();
                      final rentVal = res['rent'] ?? 8000;
                      final dueDateStr = res['due_date'] ?? '05 Nov 2026';

                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: isPending
                                ? const Color(0xFFFEF3C7)
                                : AppTheme.primaryBlue.withValues(alpha: 0.12),
                            child: Text(
                              res['name']?.toString().isNotEmpty == true ? res['name'].toString()[0].toUpperCase() : 'R',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPending ? const Color(0xFFB45309) : AppTheme.primaryBlue,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  res['name'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '+91 ${res['phone'] ?? ''}',
                                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 11.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  roomStr != null ? 'Room $roomStr' : 'Unassigned',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (bedStr != null)
                                  Text(
                                    bedStr,
                                    style: const TextStyle(color: AppTheme.textGrey, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (!isCompact) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '₹$rentVal / mo',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryBlue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Due: $dueDateStr',
                                style: const TextStyle(color: AppTheme.textGrey, fontSize: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPending ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isPending ? 'Pending' : 'Active',
                              style: TextStyle(
                                color: isPending ? const Color(0xFFB45309) : const Color(0xFF16A34A),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (isPending || res['status'] == 'Unpaid') ...[
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: () => _showReminderDialog(
                                context,
                                targetResidentName: res['name']?.toString(),
                                targetResidentId: res['id']?.toString(),
                                defaultAmount: rentVal.toString(),
                              ),
                              tooltip: 'Send Payment Reminder',
                              icon: const Icon(
                                Icons.notifications_active_outlined,
                                size: 17,
                                color: AppTheme.primaryTeal,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Summary Stat Card
  Widget _buildStatCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color valueColor,
    required bool isOutlinedButton,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textGrey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: isOutlinedButton
                  ? OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('View Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    )
                  : ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: const Text('View Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Redesigned Premium Pending Approvals Card (Enterprise SaaS Style)
class PendingApprovalsCard extends StatelessWidget {
  final List<Map<String, dynamic>> pendingResidents;
  final VoidCallback onReviewAndAssign;
  final VoidCallback? onReject;

  const PendingApprovalsCard({
    super.key,
    required this.pendingResidents,
    required this.onReviewAndAssign,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final count = pendingResidents.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final first = pendingResidents.isNotEmpty ? pendingResidents.first : <String, dynamic>{};
    final residentName = first['name'] ?? first['full_name'] ?? 'Applicant';
    final residentPhone = first['phone'] ?? first['mobile'] ?? '';
    final residentRoom = first['room'] ?? first['room_number'] ?? 'Unassigned';

    final cardBg = isDark ? AppTheme.cardBackgroundDark : Colors.white;
    final borderCol = isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0);
    final textPri = isDark ? AppTheme.primaryTextDark : AppTheme.primaryText;
    final textSec = isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.4 : 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.08 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.25),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.pending_actions_rounded,
                          color: Color(0xFFD97706),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Pending Resident Approvals',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: textPri,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD97706).withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$count Awaiting Review',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content Details & Actions
          Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 620;

                final residentInfo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryTeal, AppTheme.darkNavy],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              residentName.isNotEmpty ? residentName[0].toUpperCase() : 'A',
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                residentName,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: textPri,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (residentPhone.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.phone_outlined, size: 13, color: textSec),
                                        const SizedBox(width: 4),
                                        Text(
                                          residentPhone,
                                          style: GoogleFonts.manrope(fontSize: 12, color: textSec, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.meeting_room_outlined, size: 13, color: textSec),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Room: $residentRoom',
                                        style: GoogleFonts.manrope(fontSize: 12, color: textSec, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                  if (count > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: borderCol),
                                      ),
                                      child: Text(
                                        '+${count - 1} more applicants',
                                        style: GoogleFonts.manrope(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primaryTeal,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                final actionButtons = Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.end,
                  children: [
                    if (onReject != null)
                      OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close_rounded, size: 15, color: AppTheme.statusRed),
                        label: Text(
                          'Reject',
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.statusRed,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.statusRed.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          minimumSize: const Size(0, 38),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: onReviewAndAssign,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: Text(
                        count > 1 ? 'Review All ($count)' : 'Review & Assign',
                        style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                        minimumSize: const Size(0, 38),
                      ),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      residentInfo,
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: actionButtons,
                      ),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: residentInfo),
                    const SizedBox(width: 16),
                    actionButtons,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
