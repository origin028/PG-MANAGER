import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';

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

  void _showNoticeDialog(BuildContext context) {
    final noticeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Send Notice to all Residents'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: TextField(
            controller: noticeController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Type your announcement here...'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final text = noticeController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              try {
                final propId = AppData.selectedPropertyId ?? (AppData.properties.isNotEmpty ? AppData.properties.first['id']?.toString() : null);
                if (propId != null && propId.isNotEmpty) {
                  await AdminApiService.broadcastNotice(
                    propertyId: propId,
                    title: 'Notice to Residents',
                    message: text,
                    priority: 'NORMAL',
                  );
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notice Sent to All Residents!'), backgroundColor: AppTheme.successGreen),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to send notice: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  // Room Availability Modal showing 2-column grid of rooms with vacant beds and floor numbers
  void _showRoomAvailabilityModal(BuildContext context) {
    final availableRooms = AppData.rooms.where((room) {
      final beds = (room['beds'] as List?) ?? [];
      return beds.any((bed) => bed['status'] == 'Available');
    }).toList();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
        final itemBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
        final itemBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final textPri = isDark ? Colors.white : AppTheme.textDark;
        final textSec = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;

        return Dialog(
          backgroundColor: cardBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            width: 640,
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.bedroom_parent_rounded, color: AppTheme.successGreen, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Room Availability',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPri,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: textSec, size: 20),
                      onPressed: () => Navigator.pop(dialogCtx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2-Column Grid of Room Cards
                Flexible(
                  child: availableRooms.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No rooms with vacant beds currently available.',
                              style: TextStyle(color: AppTheme.textGrey),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          itemCount: availableRooms.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 2.5,
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
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: itemBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: itemBorder),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Top Row: Room Number (bold) & Availability (green text)
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
                                          const SizedBox(width: 8),
                                          Text(
                                            '$vacantBeds ${vacantBeds == 1 ? 'Bed' : 'Beds'} Available',
                                            style: const TextStyle(
                                              color: AppTheme.successGreen,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Bottom Row: Floor (grey text) & Sharing Type (grey text)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              floorName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: textSec,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            roomType,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textSec,
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
                ),
                const SizedBox(height: 20),

                // Modal Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text('Close', style: TextStyle(color: textSec)),
                    ),
                  ],
                ),
              ],
            ),
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
    final media = MediaQuery.sizeOf(context);
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<Uint8List?>(
        future: AdminApiService.getKycDocumentBytes(residentId, docType),
        builder: (ctx, snapshot) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    docLabel,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (media.width * 0.85).clamp(280.0, 560.0),
                maxHeight: (media.height * 0.70).clamp(220.0, 480.0),
              ),
              child: Builder(
                builder: (_) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Loading secured KYC document...'),
                          ],
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
                    return const SizedBox(
                      height: 160,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, color: Colors.grey, size: 48),
                            SizedBox(height: 8),
                            Text('Document could not be loaded or is unavailable.'),
                          ],
                        ),
                      ),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPendingApprovalsListDialog(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pending_actions_rounded, color: Color(0xFFD97706)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pending Registrations (${AppData.pendingResidents.length})',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (media.width * 0.90).clamp(300.0, 560.0),
            maxHeight: (media.height * 0.70).clamp(240.0, 480.0),
          ),
          child: AppData.pendingResidents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: Text('No pending resident registrations.')),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: AppData.pendingResidents.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final res = AppData.pendingResidents[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        child: Text(
                          res['name']?.toString().isNotEmpty == true
                              ? res['name'].toString()[0].toUpperCase()
                              : 'R',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                        ),
                      ),
                      title: Text(
                        res['name'] ?? 'Pending Resident',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('+91 ${res['phone'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                          if (res['property_name']?.toString().isNotEmpty == true)
                            Text(
                              'Property: ${res['property_name']}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAssignRoomAndRentDialog(context, res);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
          ),
        ],
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

    showDialog(
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

            showDialog(
              context: context,
              builder: (rejectCtx) => StatefulBuilder(
                builder: (rCtx, setRejectState) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: const Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Reject Registration'),
                    ],
                  ),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Please provide a mandatory reason for rejecting this resident application:',
                          style: TextStyle(fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: reasonController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'e.g. Incomplete KYC documents or invalid identity proof',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        if (rejectError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            rejectError!,
                            style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: isRejectSubmitting ? null : () => Navigator.pop(rejectCtx),
                      child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                    ),
                    ElevatedButton(
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
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: isRejectSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm Rejection'),
                    ),
                  ],
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

    // Count pending residents from AppData.pendingResidents
    final pendingCount = AppData.pendingResidents.length;

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
                      // 1. Premium Welcome Banner with Soft Gradients
                      _buildWelcomeBanner(context, pendingCount),
                      const SizedBox(height: 20),

                      // Bed Capacity Card (Fixed 240 Beds)
                      _buildBedCapacityCard(context),
                      const SizedBox(height: 20),

                      // 2. Pending Resident Approvals Card (if pendingCount > 0)
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
                        ),
                        const SizedBox(height: 20),
                      ],

                      // 3. Stat Cards Row
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 650;
                          if (isMobile) {
                            return Column(
                              children: [
                                _buildStatCard(
                                  title: 'Rent Overview',
                                  subtitle: 'Tenants Unpaid',
                                  value: _dashboardStats.isNotEmpty ? '${_dashboardStats['total_residents'] ?? 0} / ${_dashboardStats['pending_rent'] ?? 0}' : '${currentData['totalTenants']} / ${currentData['unpaid']}',
                                  icon: Icons.account_balance_wallet_rounded,
                                  iconColor: AppTheme.primaryBlue,
                                  valueColor: AppTheme.primaryBlue,
                                  isOutlinedButton: false,
                                  onTap: () => context.go('/payments'),
                                ),
                                const SizedBox(height: 16),
                                _buildStatCard(
                                  title: 'Room Availability',
                                  subtitle: 'Beds Available',
                                  value: _dashboardStats.isNotEmpty && _dashboardStats['vacant_beds'] != null ? _dashboardStats['vacant_beds'].toString() : realAvailableBeds.toString(),
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
                                  value: _dashboardStats.isNotEmpty ? '${_dashboardStats['total_residents'] ?? 0} / ${_dashboardStats['pending_rent'] ?? 0}' : '${currentData['totalTenants']} / ${currentData['unpaid']}',
                                  icon: Icons.account_balance_wallet_rounded,
                                  iconColor: AppTheme.primaryBlue,
                                  valueColor: AppTheme.primaryBlue,
                                  isOutlinedButton: false,
                                  onTap: () => context.go('/payments'),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _buildStatCard(
                                  title: 'Room Availability',
                                  subtitle: 'Beds Available',
                                  value: _dashboardStats.isNotEmpty && _dashboardStats['vacant_beds'] != null ? _dashboardStats['vacant_beds'].toString() : realAvailableBeds.toString(),
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
                      ),

                      const SizedBox(height: 28),

                      // Manage PG Section
                      const Text(
                        'Manage PG',
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold, 
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildQuickAction(Icons.person_add_alt_1_rounded, 'Tenant', () => context.go('/residents')),
                          _buildQuickAction(Icons.account_balance_wallet_outlined, 'Rent', () => context.go('/payments')),
                          _buildQuickAction(Icons.campaign_outlined, 'Notify', () => _showNoticeDialog(context)),
                          _buildQuickAction(Icons.receipt_long_outlined, 'Bills', () => context.go('/payments')),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // 5. Main Residents Table
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

  // Welcome Banner Widget
  Widget _buildWelcomeBanner(BuildContext context, int pendingCount) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0052CC), Color(0xFF0066FF), Color(0xFF38BDF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background ambient circles
          Positioned(
            right: -20,
            bottom: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 80,
            top: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded, color: Colors.white, size: 13),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '$_selectedProperty • Operations Active',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Welcome, Property Manager 👋',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.3),
              ),
              const SizedBox(height: 6),
              const Text(
                'Monitor resident self-onboardings, assign rooms, and manage monthly rent distributions seamlessly.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Main Residents Table (displays residents and updates dynamically when room/rent is assigned)
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

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xFF0F172A), size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}

// Pending Approvals Card matching reference UI (Yellow background, orange border)
class PendingApprovalsCard extends StatelessWidget {
  final List<Map<String, dynamic>> pendingResidents;
  final VoidCallback onReviewAndAssign;

  const PendingApprovalsCard({
    super.key,
    required this.pendingResidents,
    required this.onReviewAndAssign,
  });

  @override
  Widget build(BuildContext context) {
    final count = pendingResidents.length;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 18, vertical: isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3), // Yellow background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF97316), // Orange border
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 540;

          final iconWidget = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.assignment_ind_rounded, color: Colors.white, size: 22),
          );

          final textSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'Pending Resident Approvals',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF7C2D12),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEA580C).withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      '$count PENDING',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$count applicant${count > 1 ? 's' : ''} awaiting room & rent assignment.',
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );

          final reviewButton = ElevatedButton(
            onPressed: onReviewAndAssign,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count > 1 ? 'Review All ($count)' : 'Review & Assign',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWidget,
                    const SizedBox(width: 12),
                    Expanded(child: textSection),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: reviewButton,
                ),
              ],
            );
          }

          return Row(
            children: [
              iconWidget,
              const SizedBox(width: 14),
              Expanded(child: textSection),
              const SizedBox(width: 12),
              reviewButton,
            ],
          );
        },
      ),
    );
  }
}