import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../residents/residents_screen.dart';

class RoomsBedsScreen extends StatefulWidget {
  final String? initialRoom;
  const RoomsBedsScreen({super.key, this.initialRoom});

  @override
  State<RoomsBedsScreen> createState() => _RoomsBedsScreenState();
}

class _RoomsBedsScreenState extends State<RoomsBedsScreen> {
  late TextEditingController _searchController;
  String _searchQuery = '';
  String? _highlightedRoom;

  @override
  void initState() {
    super.initState();
    final init = widget.initialRoom ?? AppData.selectedRoomForHighlight;
    _searchQuery = init ?? '';
    _highlightedRoom = (init != null && init.trim().isNotEmpty) ? init.trim() : null;
    _searchController = TextEditingController(text: _searchQuery);
    AppData.selectedRoomForHighlight = null;
    AppData.selectedPropertyIdNotifier.addListener(_loadRoomsFromApi);
    _loadRoomsFromApi();
  }

  void _loadRoomsFromApi() async {
    final propId = AppData.selectedPropertyId;
    if (propId == null || propId.isEmpty || propId.startsWith('p')) return;
    try {
      final floorGroups = await AdminApiService.getFloorRooms(propId);
      if (floorGroups.isNotEmpty && mounted) {
        List<Map<String, dynamic>> apiRooms = [];
        for (var fg in floorGroups) {
          final floorNum = fg['floor_number'] ?? 1;
          final floorLabel = floorNum == 0 ? 'Ground Floor' : '${floorNum}st Floor';
          final rooms = (fg['rooms'] as List?) ?? [];
          for (var r in rooms) {
            final totalBeds = (r['total_beds'] as int?) ?? 2;
            final occBeds = (r['occupied_beds'] as int?) ?? 0;
            List<Map<String, dynamic>> beds = [];
            for (int i = 0; i < totalBeds; i++) {
              beds.add({
                'name': 'Bed ${String.fromCharCode(65 + i)}',
                'status': i < occBeds ? 'Occupied' : 'Available',
                'occupant': i < occBeds ? 'Occupied' : null,
              });
            }
            apiRooms.add({
              'id': r['id']?.toString(),
              'number': r['room_number']?.toString() ?? '',
              'floor': floorLabel,
              'type': r['room_type'] ?? '2-Sharing',
              'beds': beds,
            });
          }
        }
        if (apiRooms.isNotEmpty) {
          setState(() {
            AppData.rooms = apiRooms;
          });
        }
      }
    } catch (e) {
      debugPrint('API getFloorRooms error: $e');
    }
  }

  @override
  void didUpdateWidget(RoomsBedsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoom != oldWidget.initialRoom && widget.initialRoom != null) {
      setState(() {
        _searchQuery = widget.initialRoom!;
        _highlightedRoom = widget.initialRoom!.trim();
        _searchController.text = widget.initialRoom!;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rooms {
    if (_searchQuery.trim().isEmpty) return AppData.rooms;
    final q = _searchQuery.trim().toLowerCase();
    return AppData.rooms.where((room) {
      final num = (room['number'] ?? '').toString().toLowerCase();
      final floor = (room['floor'] ?? '').toString().toLowerCase();
      final type = (room['type'] ?? '').toString().toLowerCase();
      final beds = (room['beds'] as List?) ?? [];
      final matchOccupant = beds.any((b) => (b['occupant'] ?? '').toString().toLowerCase().contains(q));
      return num.contains(q) || floor.contains(q) || type.contains(q) || matchOccupant;
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _getGroupedRooms() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var room in _rooms) {
      final floor = room['floor'] ?? '1st Floor';
      if (!grouped.containsKey(floor)) grouped[floor] = [];
      grouped[floor]!.add(room);
    }
    return grouped;
  }

  void _showAddRoomDialog() {
    final numberController = TextEditingController();
    String selectedFloor = '1st Floor';
    String selectedType = '2-Sharing';
    final bedCountController = TextEditingController(text: '2');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderCtx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: const Text('Add New Room', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: numberController,
                        decoration: const InputDecoration(
                          labelText: 'Room Number (e.g. 104) *',
                          hintText: 'e.g. 104',
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedFloor,
                        decoration: AppTheme.formDropdownDecoration(labelText: 'Select Floor'),
                        borderRadius: BorderRadius.circular(12),
                        elevation: 2,
                        dropdownColor: Colors.white,
                        icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                        items: ['Ground Floor', '1st Floor', '2nd Floor', '3rd Floor', '4th Floor'].map((floor) {
                          return DropdownMenuItem(value: floor, child: Text(floor));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedFloor = val);
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedType,
                              decoration: AppTheme.formDropdownDecoration(labelText: 'Room Type'),
                              borderRadius: BorderRadius.circular(12),
                              elevation: 2,
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                              items: ['Single Sharing', '2-Sharing', '3-Sharing', '4-Sharing'].map((t) {
                                return DropdownMenuItem(value: t, child: Text(t));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    selectedType = val;
                                    if (val == 'Single Sharing') bedCountController.text = '1';
                                    if (val == '2-Sharing') bedCountController.text = '2';
                                    if (val == '3-Sharing') bedCountController.text = '3';
                                    if (val == '4-Sharing') bedCountController.text = '4';
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: bedCountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Beds'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    String roomNo = numberController.text.trim();

                    if (roomNo.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Please enter a room number!'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    if (AppData.roomExists(roomNo)) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Error: Room $roomNo already exists!'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    int bedCount = int.tryParse(bedCountController.text) ?? 1;
                    if (bedCount < 1) bedCount = 1;

                    List<Map<String, dynamic>> newBeds = List.generate(bedCount, (index) {
                      return {
                        'name': 'Bed ${String.fromCharCode(65 + index)}',
                        'status': 'Available',
                        'occupant': null,
                      };
                    });

                    final propId = AppData.selectedPropertyId;
                    String? createdRoomId;
                    if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                      int floorNum = 1;
                      if (selectedFloor.contains('Ground')) {
                        floorNum = 0;
                      } else if (selectedFloor.contains('1')) {
                        floorNum = 1;
                      } else if (selectedFloor.contains('2')) {
                        floorNum = 2;
                      } else if (selectedFloor.contains('3')) {
                        floorNum = 3;
                      } else if (selectedFloor.contains('4')) {
                        floorNum = 4;
                      }

                      try {
                        final createdRoom = await AdminApiService.createRoom({
                          'property_id': propId,
                          'room_number': roomNo,
                          'floor_number': floorNum,
                          'room_type': selectedType.contains('Single') ? 'SINGLE' : (selectedType.contains('2') ? 'DOUBLE' : (selectedType.contains('3') ? 'TRIPLE' : 'OTHER')),
                          'base_monthly_rent': 8000,
                          'deposit_amount': 10000,
                          'max_occupancy': bedCount,
                        });
                        if (createdRoom.isNotEmpty && createdRoom['id'] != null) {
                          createdRoomId = createdRoom['id'].toString();
                          await Future.wait(List.generate(bedCount, (i) {
                            return AdminApiService.createBed({
                              'room_id': createdRoom['id'],
                              'bed_number': String.fromCharCode(65 + i),
                              'monthly_rent': 8000,
                            });
                          }));
                          _loadRoomsFromApi();
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to add room: $e'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }
                    }

                    final newRoom = <String, dynamic>{
                      'number': roomNo,
                      'floor': selectedFloor,
                      'type': selectedType,
                      'beds': newBeds,
                    };
                    if (createdRoomId != null) {
                      newRoom['id'] = createdRoomId;
                    }

                    if (!mounted) return;
                    setState(() {
                      AppData.rooms.add(newRoom);
                      AppData.saveRoomsToStorage();
                    });

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Room $roomNo added on $selectedFloor!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Add Room'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManageRoomModal(BuildContext context, Map<String, dynamic> room) {
    final roomNumber = room['number']?.toString() ?? '';
    final floor = room['floor']?.toString() ?? '1st Floor';
    final type = room['type']?.toString() ?? 'Standard';
    final beds = (room['beds'] as List?) ?? [];
    final occupiedBeds = beds.where((b) => b['status'] == 'Occupied').length;
    final vacantBeds = beds.length - occupiedBeds;

    showDialog(
      context: context,
      builder: (modalCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.meeting_room, color: AppTheme.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Manage Room $roomNumber',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildManageDetailRow('Room Number', 'Room $roomNumber'),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildManageDetailRow('Floor', floor),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildManageDetailRow('Sharing Type', type),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildManageDetailRow(
                  'Bed Status',
                  '$occupiedBeds Occupied, $vacantBeds Vacant (${beds.length} Total)',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (confirmCtx) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            title: const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete Room', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            content: const Text(
                              'Are you sure? This will remove all bed data',
                              style: TextStyle(fontSize: 14),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(confirmCtx),
                                child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () async {
                                  Navigator.pop(confirmCtx);
                                  Navigator.pop(modalCtx);
                                  final roomId = room['id']?.toString();
                                  if (roomId != null && roomId.isNotEmpty && !roomId.startsWith('r-')) {
                                    try {
                                      await AdminApiService.deleteRoom(roomId);
                                      _loadRoomsFromApi();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Room $roomNumber deleted successfully'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Cannot delete Room $roomNumber: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                  } else {
                                    setState(() {
                                      AppData.rooms.removeWhere((r) => r['number'].toString() == roomNumber);
                                      AppData.saveRoomsToStorage();
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Room $roomNumber deleted successfully'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Delete Room', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                    label: const Text('Delete Room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(modalCtx),
              child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildManageDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark, fontSize: 13),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showBedManagerModal(BuildContext context, int roomIndex) {
    if (roomIndex < 0 || roomIndex >= AppData.rooms.length) {
      if (AppData.rooms.isNotEmpty) {
        roomIndex = 0;
      } else {
        return;
      }
    }
    final room = AppData.rooms[roomIndex];
    final beds = (room['beds'] as List?) ?? [];

    void openAddResident(BuildContext dialogCtx) {
      Navigator.pop(dialogCtx);
      ResidentsScreen.showAddResidentDialog(
        context,
        prefilledRoom: room['number'].toString(),
        prefilledFloor: room['floor']?.toString(),
        onComplete: () {
          setState(() {});
          if (mounted) {
            _showBedManagerModal(context, roomIndex);
          }
        },
      );
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Room ${room['number']}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            ),
                            Text(
                              '${room['type'] ?? 'Standard'} • ${room['floor'] ?? 'Floor 1'}',
                              style: const TextStyle(color: AppTheme.textGrey),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 'Add Resident' button in Deep Purple (Colors.deepPurple)
                      ElevatedButton.icon(
                        onPressed: () => openAddResident(dialogCtx),
                        icon: const Icon(Icons.person_add, size: 18, color: Colors.white),
                        label: const Text('Add Resident', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  
                  // Bed List
                  ...beds.map((bed) {
                    final isOccupied = bed['status'] == 'Occupied';
                    final occupantName = bed['occupant'] ?? 'Unknown';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppTheme.inputBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: isOccupied
                            ? () {
                                Navigator.pop(dialogCtx);
                                _showResidentProfileModal(context, occupantName);
                              }
                            : () => openAddResident(dialogCtx),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (bed['name'] ?? 'Bed').toString().toUpperCase(),
                                style: const TextStyle(color: AppTheme.textGrey, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.king_bed_rounded,
                                    size: 24,
                                    color: isOccupied ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      isOccupied ? occupantName : 'Empty Bed',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isOccupied ? AppTheme.textDark : AppTheme.textGrey,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isOccupied) ...[
                                    // Rent text in Deep Purple (Colors.deepPurple), NOT Orange
                                    Text(
                                      '₹${bed['rent'] ?? 7000}/mo',
                                      style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  // Hamburger Icon Action (Icons.drag_handle) wrapped in IconButton
                                  if (isOccupied)
                                    IconButton(
                                      icon: const Icon(Icons.drag_handle, color: AppTheme.textGrey),
                                      tooltip: 'View Resident Profile',
                                      onPressed: () {
                                        Navigator.pop(dialogCtx);
                                        _showResidentProfileModal(context, occupantName);
                                      },
                                    )
                                  else
                                    ElevatedButton.icon(
                                      onPressed: () => openAddResident(dialogCtx),
                                      icon: const Icon(Icons.person_add_alt_1, size: 14, color: Colors.white),
                                      label: const Text(
                                        'Add Resident',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.deepPurple,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 32),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                  }),
                  
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Close', style: TextStyle(color: AppTheme.textDark)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Full Resident Profile Modal (Step 4)
  void _showResidentProfileModal(BuildContext context, String residentName) {
    final resident = AppData.residents.firstWhere(
      (r) => (r['name'] ?? '').toString().trim().toLowerCase() == residentName.trim().toLowerCase(),
      orElse: () {
        final found = AppData.getResidentByName(residentName);
        if (found != null) return found;
        return <String, dynamic>{
          'name': residentName,
          'phone': '9876543210',
          'email': '${residentName.toLowerCase().replaceAll(' ', '.')}@example.com',
          'emergency_contact': '9876543299',
          'room': '101',
          'bed': 'Bed A',
          'rent': 7000,
          'deposit': 14000,
          'status': 'Active',
          'property_name': 'Sunshine PG',
          'joining_date': '01 Jan 2026',
          'dob': '15/05/1998',
          'gender': 'Male',
          'occupation': 'Software Engineer',
          'address': '#14, 2nd Cross, Indira Nagar, Bengaluru',
          'pincode': '560038',
          'aadhaar_number': 'Not provided',
          'pan_number': 'Not provided',
        };
      },
    );

    ResidentsScreen.showResidentProfileModal(
      context,
      resident,
      onStateChanged: () => setState(() {}),
    );
  }

  // Top Summary Pill Helper Widget: Rooms & Beds
  Widget _buildSummaryPill({
    required IconData icon,
    required String label,
    required int total,
    required int occupied,
    required int empty,
    required String emptyLabel,
    bool isMobile = false,
  }) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - (isMobile ? 32 : 48),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 18,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isMobile ? 18 : 20, color: AppTheme.primaryBlue),
            SizedBox(width: isMobile ? 6 : 8),
            Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
                fontSize: isMobile ? 13 : 14,
              ),
            ),
            SizedBox(width: isMobile ? 6 : 10),
            Text(
              'Total $total',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
                fontSize: isMobile ? 12 : 13,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10),
              child: Text('|', style: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.bold)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  'Occupied $occupied',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF16A34A),
                    fontSize: isMobile ? 12 : 13,
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10),
              child: Text('|', style: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.bold)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  '$emptyLabel $empty',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFDC2626),
                    fontSize: isMobile ? 12 : 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedRooms = _getGroupedRooms();
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Calculate summary numbers dynamically
    final totalRooms = AppData.rooms.length;
    int occupiedRooms = AppData.rooms.where((r) => ((r['beds'] as List?) ?? []).any((b) => b['status'] == 'Occupied')).length;
    int emptyRooms = totalRooms - occupiedRooms;

    int totalBeds = 0;
    int totalOccupiedBeds = 0;
    int totalVacantBeds = 0;
    for (var r in AppData.rooms) {
      final beds = (r['beds'] as List?) ?? [];
      for (var b in beds) {
        totalBeds++;
        if (b['status'] == 'Occupied') {
          totalOccupiedBeds++;
        } else {
          totalVacantBeds++;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title
          const Text(
            'Rooms & Beds',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 18),

          // 1. Top Summary Row: Two Pill-Shaped Containers
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _buildSummaryPill(
                icon: Icons.meeting_room_outlined,
                label: 'Rooms',
                total: totalRooms,
                occupied: occupiedRooms,
                empty: emptyRooms,
                emptyLabel: 'Empty',
                isMobile: isMobile,
              ),
              _buildSummaryPill(
                icon: Icons.king_bed_outlined,
                label: 'Beds',
                total: totalBeds,
                occupied: totalOccupiedBeds,
                empty: totalVacantBeds,
                emptyLabel: 'Vacant',
                isMobile: isMobile,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action & Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 750;
                final searchField = TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _highlightedRoom = val.trim().isNotEmpty ? val.trim() : null;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by room number, floor, type, or occupant...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textGrey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _highlightedRoom = null;
                              });
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                );

                final addBtn = ElevatedButton.icon(
                  onPressed: _showAddRoomDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Room', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    minimumSize: const Size(130, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );

                final legend = Wrap(
                  spacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildLegend(const Color(0xFF16A34A), 'Occupied'),
                    _buildLegend(const Color(0xFF94A3B8), 'Vacant'),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          addBtn,
                          legend,
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 14),
                    addBtn,
                    const SizedBox(width: 16),
                    legend,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Room Cards Grid
          Expanded(
            child: _rooms.isEmpty
                ? EmptyState(
                    icon: _searchQuery.isNotEmpty ? Icons.search_off_outlined : Icons.king_bed_outlined,
                    title: _searchQuery.isNotEmpty ? 'No matching rooms found' : 'No rooms yet',
                    subtitle: _searchQuery.isNotEmpty
                        ? 'No rooms match "$_searchQuery". Try searching for a different room number or floor.'
                        : 'Add your first room to manage beds and assignments',
                    actionLabel: _searchQuery.isNotEmpty ? 'Clear Search' : 'Add Room',
                    onAction: _searchQuery.isNotEmpty
                        ? () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _highlightedRoom = null;
                            });
                          }
                        : _showAddRoomDialog,
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: groupedRooms.keys.map((floor) {
                        final floorRooms = groupedRooms[floor]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12, top: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.layers, color: AppTheme.primaryBlue, size: 20),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      floor,
                                      style: TextStyle(
                                        fontSize: isMobile ? 16 : 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '(${floorRooms.length} rooms)',
                                    style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: MediaQuery.of(context).size.width < 600
                                    ? 2
                                    : (MediaQuery.of(context).size.width < 1000 ? 3 : 4),
                                childAspectRatio: isMobile ? 0.98 : 1.45,
                                crossAxisSpacing: isMobile ? 10 : 14,
                                mainAxisSpacing: isMobile ? 10 : 14,
                              ),
                              itemCount: floorRooms.length,
                              itemBuilder: (context, index) {
                                final room = floorRooms[index];
                                final beds = (room['beds'] as List?) ?? [];
                                int occupiedBeds = beds.where((b) => b['status'] == 'Occupied').length;
                                int vacantBeds = beds.length - occupiedBeds;
                                int mainIndex = AppData.rooms.indexWhere((r) => r['number'].toString() == room['number'].toString());
                                if (mainIndex == -1) mainIndex = AppData.rooms.indexOf(room);
                                if (mainIndex == -1) mainIndex = 0;

                                final roomNumberStr = (room['number'] ?? '').toString().trim();
                                final isHighlighted = _highlightedRoom != null &&
                                    _highlightedRoom!.trim().isNotEmpty &&
                                    (roomNumberStr.toLowerCase() == _highlightedRoom!.trim().toLowerCase());

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => _showBedManagerModal(context, mainIndex),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 8 : 14,
                                        vertical: isMobile ? 8 : 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isHighlighted ? const Color(0xFFF0FDF4) : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isHighlighted ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                                          width: isHighlighted ? 2.0 : 1.0,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: isHighlighted
                                                ? AppTheme.primaryBlue.withValues(alpha: 0.18)
                                                : Colors.black.withValues(alpha: 0.03),
                                            blurRadius: isHighlighted ? 8 : 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Top Row: Room Number (Bold) on left, Sharing Type in light grey on right + Edit Icon
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'Room ${room['number']}',
                                                  style: TextStyle(
                                                    fontSize: isMobile ? 13 : 15,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.textDark,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        room['type'] ?? 'Standard',
                                                        style: TextStyle(
                                                          color: AppTheme.textGrey,
                                                          fontSize: isMobile ? 11 : 12,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    InkWell(
                                                      onTap: () => _showManageRoomModal(context, room),
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(2),
                                                        child: Icon(
                                                          Icons.edit_outlined,
                                                          size: isMobile ? 15 : 17,
                                                          color: AppTheme.textGrey,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Middle: Centered Bed Icons in rounded square boxes
                                          Padding(
                                            padding: EdgeInsets.symmetric(vertical: isMobile ? 2 : 6),
                                            child: Center(
                                              child: Wrap(
                                                alignment: WrapAlignment.center,
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: beds.map((bed) {
                                                  final isOccupied = bed['status'] == 'Occupied';
                                                  return Container(
                                                    width: isMobile ? 28 : 36,
                                                    height: isMobile ? 28 : 36,
                                                    decoration: BoxDecoration(
                                                      color: isOccupied ? const Color(0xFF86EFAC) : Colors.white,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: isOccupied ? const Color(0xFF4ADE80) : const Color(0xFFE2E8F0),
                                                        width: 1.2,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.bed_outlined,
                                                        color: const Color(0xFF4338CA),
                                                        size: isMobile ? 16 : 20,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                          // Bottom Row (Divider above it): 2-column stats layout with proper alignment
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Divider(height: 10, thickness: 1, color: Color(0xFFF1F5F9)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          '$occupiedBeds',
                                                          style: TextStyle(
                                                            color: const Color(0xFF16A34A),
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: isMobile ? 13 : 15,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          'Occupied',
                                                          style: TextStyle(
                                                            color: AppTheme.textGrey,
                                                            fontWeight: FontWeight.w500,
                                                            fontSize: isMobile ? 10 : 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    height: 22,
                                                    width: 1,
                                                    color: const Color(0xFFE2E8F0),
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          '$vacantBeds',
                                                          style: TextStyle(
                                                            color: const Color(0xFF475569),
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: isMobile ? 13 : 15,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          'Vacant',
                                                          style: TextStyle(
                                                            color: AppTheme.textGrey,
                                                            fontWeight: FontWeight.w500,
                                                            fontSize: isMobile ? 10 : 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
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
                            const SizedBox(height: 20),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.king_bed_rounded, color: color, size: 20),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
      ],
    );
  }
}