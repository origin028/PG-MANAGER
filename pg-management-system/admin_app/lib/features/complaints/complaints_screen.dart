import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/table_components.dart';
import '../../core/widgets/app_dropdown.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_loadComplaintsFromApi);
    _loadComplaintsFromApi();
  }

  void _loadComplaintsFromApi() async {
    final propId = AppData.selectedPropertyId;
    try {
      final list = await AdminApiService.getComplaints(propertyId: propId);
      if (list.isNotEmpty && mounted) {
        setState(() {
          AppData.complaints = list.map((c) => <String, dynamic>{
            'id': c['id']?.toString() ?? '',
            'title': c['title'] ?? 'Complaint',
            'description': c['description'] ?? '',
            'resident': c['resident_name'] ?? 'Resident',
            'room': c['room_number'] ?? '101',
            'property': c['property_name'] ?? AppData.selectedProperty,
            'status': c['status'] == 'RESOLVED' ? 'Resolved' : (c['status'] == 'IN_PROGRESS' ? 'In Progress' : 'Pending'),
            'priority': c['priority'] ?? 'Medium',
            'date': c['created_at']?.toString().substring(0, 10) ?? '2026-10-15',
            'category': c['category'] ?? 'General',
            'assigned_staff': c['assigned_staff_name'] ?? 'Staff',
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('API getComplaints error: $e');
    }
  }
  String _searchQuery = '';
  String _selectedStatus = 'All Statuses';
  String _selectedPriority = 'All Priorities';

  // Shared Complaints from AppData (persists across navigation)
  List<Map<String, dynamic>> get _complaints => AppData.complaints;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredComplaints {
    return _complaints.where((c) {
      final query = _searchQuery.toLowerCase().trim();
      if (query.isNotEmpty) {
        final title = (c['title'] ?? '').toString().toLowerCase();
        final desc = (c['description'] ?? '').toString().toLowerCase();
        final res = (c['resident'] ?? '').toString().toLowerCase();
        final rm = (c['room'] ?? '').toString().toLowerCase();
        final prop = (c['property'] ?? '').toString().toLowerCase();
        final id = (c['id'] ?? '').toString().toLowerCase();
        if (!title.contains(query) &&
            !desc.contains(query) &&
            !res.contains(query) &&
            !rm.contains(query) &&
            !prop.contains(query) &&
            !id.contains(query)) {
          return false;
        }
      }

      if (_selectedStatus != 'All Statuses') {
        final st = (c['status'] ?? '').toString().trim();
        if (st.toLowerCase() != _selectedStatus.toLowerCase()) {
          return false;
        }
      }

      if (_selectedPriority != 'All Priorities') {
        final pri = (c['priority'] ?? '').toString().trim();
        if (pri.toLowerCase() != _selectedPriority.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildPriorityPill(String priority) {
    Color color;
    Color bg;

    if (priority.toLowerCase() == 'high') {
      color = const Color(0xFFDC2626);
      bg = const Color(0xFFFEF2F2);
    } else if (priority.toLowerCase() == 'medium') {
      color = const Color(0xFFD97706);
      bg = const Color(0xFFFFFBEB);
    } else {
      color = const Color(0xFF2563EB);
      bg = const Color(0xFFEFF6FF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildComplaintStatusDot(String status) {
    Color dotColor;
    if (status.toLowerCase() == 'resolved') {
      dotColor = const Color(0xFF10B981); // Green dot Resolved
    } else if (status.toLowerCase() == 'assigned') {
      dotColor = const Color(0xFFEF4444); // Red dot Assigned
    } else if (status.toLowerCase() == 'in progress') {
      dotColor = const Color(0xFFF59E0B); // Orange dot In Progress
    } else {
      dotColor = const Color(0xFF94A3B8); // Grey dot Pending
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 6),
        Text(
          status,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dotColor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final openTickets = _complaints.where((c) => c['status'] != 'Resolved').length;
    final highPriority = _complaints.where((c) => c['priority'] == 'High').length;
    final inProgress = _complaints.where((c) => c['status'] == 'In Progress').length;
    final resolvedCount = _complaints.where((c) => c['status'] == 'Resolved').length;
    final filtered = _filteredComplaints;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final titleSection = const Text('Complaints & Service Requests', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark));

              final addBtn = ElevatedButton.icon(
                onPressed: _showAddComplaintDialog,
                icon: const Icon(Icons.add_alert, size: 18),
                label: const Text('Log Complaint'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(140, 44)),
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    const SizedBox(height: 12),
                    addBtn,
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  titleSection,
                  addBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // 1. KPI Summary Cards
          TableKpiGrid(
            cards: [
              TableKpiCard(
                title: 'Open Tickets',
                value: '$openTickets',
                subtitle: 'Action required',
                icon: Icons.mark_email_unread_outlined,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFFFBEB),
              ),
              TableKpiCard(
                title: 'High Priority',
                value: '$highPriority',
                subtitle: 'Urgent attention',
                icon: Icons.priority_high_rounded,
                iconColor: const Color(0xFFDC2626),
                iconBgColor: const Color(0xFFFEF2F2),
              ),
              TableKpiCard(
                title: 'In Progress',
                value: '$inProgress',
                subtitle: 'Assigned to technicians',
                icon: Icons.pending_actions_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
              ),
              TableKpiCard(
                title: 'Resolved Tickets',
                value: '$resolvedCount',
                subtitle: 'Completed requests',
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Filter Bar: 'All Statuses' and 'All Categories' dropdowns
          Container(
            padding: const EdgeInsets.all(16),
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
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search complaints by title, resident, room...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textGrey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                );

                final statusDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedStatus,
                  items: const ['All Statuses', 'Assigned', 'In Progress', 'Pending', 'Resolved'],
                  onChanged: (v) => setState(() => _selectedStatus = v),
                );

                final priorityDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedPriority,
                  items: const ['All Priorities', 'High', 'Medium', 'Low'],
                  onChanged: (v) => setState(() => _selectedPriority = v),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: statusDropdown),
                          const SizedBox(width: 10),
                          Expanded(child: priorityDropdown),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    SizedBox(width: 175, child: statusDropdown),
                    const SizedBox(width: 12),
                    SizedBox(width: 175, child: priorityDropdown),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // 3. Data Table
          Expanded(
            child: Container(
              decoration: modernTableDecoration,
              child: filtered.isEmpty
                  ? EmptyState(
                      icon: Icons.report_problem_outlined,
                      title: 'No complaints found',
                      subtitle: _searchQuery.isNotEmpty || _selectedStatus != 'All Statuses' || _selectedPriority != 'All Priorities'
                          ? 'Try adjusting your search filters'
                          : 'All residents are happy! New complaints will appear here',
                      actionLabel: 'Log Complaint',
                      onAction: _showAddComplaintDialog,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                dataRowMinHeight: 64,
                                dataRowMaxHeight: 72,
                                columnSpacing: 24,
                                horizontalMargin: 24,
                                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                headingRowHeight: 48,
                                dataRowColor: modernRowColor,
                                border: const TableBorder(
                                  horizontalInside: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                                ),
                                columns: [
                                  modernTableColumn('COMPLAINT TITLE'),
                                  modernTableColumn('CATEGORY'),
                                  modernTableColumn('RESIDENT & ROOM'),
                                  modernTableColumn('PROPERTY'),
                                  modernTableColumn('PRIORITY'),
                                  modernTableColumn('ASSIGNED STAFF'),
                                  modernTableColumn('STATUS'),
                                  modernTableColumn('DATE'),
                                  modernTableColumn('ACTIONS'),
                                ],
                                rows: filtered.map((comp) {
                                  return DataRow(cells: [
                                    // COMPLAINT TITLE (with subtitle description below it)
                                    DataCell(
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              comp['title'] ?? '',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 13),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              comp['description'] ?? '',
                                              style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // CATEGORY (rounded grey pill e.g., 'Cleaning')
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          comp['category'] ?? 'Cleaning',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                        ),
                                      ),
                                    ),
                                    // RESIDENT & ROOM (Avatar icon + Name + '(Rm 201)')
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableAvatar(name: comp['resident'] ?? 'R', radius: 15),
                                          const SizedBox(width: 10),
                                          Text(
                                            '${comp['resident']} (Rm ${comp['room']})',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textDark),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // PROPERTY
                                    DataCell(
                                      Text(
                                        comp['property'] ?? 'Green View PG - Hebbal',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                                      ),
                                    ),
                                    // PRIORITY (Blue, Orange, Red pills)
                                    DataCell(
                                      _buildPriorityPill(comp['priority'] ?? 'Medium'),
                                    ),
                                    // ASSIGNED STAFF (Name)
                                    DataCell(
                                      Text(
                                        comp['assigned_staff'] ?? 'Unassigned',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: comp['assigned_staff'] != null && comp['assigned_staff'] != 'Unassigned'
                                              ? AppTheme.textDark
                                              : AppTheme.textGrey,
                                        ),
                                      ),
                                    ),
                                    // STATUS (Red dot Assigned, Green dot Resolved, etc.)
                                    DataCell(
                                      _buildComplaintStatusDot(comp['status'] ?? 'Pending'),
                                    ),
                                    // DATE
                                    DataCell(
                                      Text(
                                        comp['date'] ?? '',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
                                      ),
                                    ),
                                    // ACTIONS ('Update / Resolve' button)
                                    DataCell(
                                      OutlinedButton.icon(
                                        onPressed: () => _showUpdateStatusModal(comp),
                                        icon: const Icon(Icons.tune, size: 14, color: AppTheme.primaryBlue),
                                        label: const Text(
                                          'Update / Resolve',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Color(0xFFBFDBFE)),
                                          backgroundColor: const Color(0xFFEFF6FF),
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                      ),
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Modal to log new complaint
  void _showAddComplaintDialog() {
    final residentController = TextEditingController();
    final roomController = TextEditingController();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String priority = 'Medium';
    String category = 'Cleaning';
    String property = 'Green View PG - Hebbal';
    String staff = 'Ramesh (Electrician)';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Log New Complaint'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Complaint Title *', hintText: 'e.g. AC cooling malfunctioning'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(labelText: 'Issue Description *', hintText: 'e.g. Compressor stops every 10 mins'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: residentController,
                              decoration: const InputDecoration(labelText: 'Resident Name *', hintText: 'e.g. Rahul Sharma'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: roomController,
                              decoration: const InputDecoration(labelText: 'Room *', hintText: 'e.g. 101'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: category,
                              decoration: const InputDecoration(labelText: 'Category'),
                              items: ['Cleaning', 'Plumbing', 'Electrical', 'Internet', 'Appliance', 'Other']
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => category = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: priority,
                              decoration: const InputDecoration(labelText: 'Priority'),
                              items: ['Low', 'Medium', 'High']
                                  .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => priority = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: property,
                        decoration: const InputDecoration(labelText: 'Property'),
                        items: ['Green View PG - Hebbal', 'BNR Luxury PG', 'Skyline Girls PG']
                            .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => property = val);
                        },
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
                  onPressed: () {
                    String resident = residentController.text.trim();
                    String room = roomController.text.trim();
                    String title = titleController.text.trim();
                    String desc = descriptionController.text.trim();

                    if (resident.isEmpty || room.isEmpty || title.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Please fill in title, resident, and room'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final newId = 'CMP-00${_complaints.length + 1}';
                    setState(() {
                      _complaints.insert(0, {
                        'id': newId,
                        'title': title,
                        'description': desc.isNotEmpty ? desc : title,
                        'category': category,
                        'resident': resident,
                        'room': room,
                        'property': property,
                        'priority': priority,
                        'assigned_staff': staff,
                        'status': 'Assigned',
                        'date': 'Today',
                      });
                    });

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Complaint $newId logged successfully!'), backgroundColor: Colors.green),
                    );
                  },
                  child: const Text('Submit Ticket'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Modal to update status
  void _showUpdateStatusModal(Map<String, dynamic> complaint) {
    String currentStatus = complaint['status'] ?? 'Pending';
    String assignedStaff = complaint['assigned_staff'] ?? 'Ramesh (Electrician)';
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Update / Resolve: ${complaint['id']}', overflow: TextOverflow.ellipsis),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complaint['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Resident: ${complaint['resident']} • Room ${complaint['room']}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: currentStatus,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: ['Assigned', 'In Progress', 'Pending', 'Resolved'].map((String status) {
                        return DropdownMenuItem(value: status, child: Text(status));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setStateModal(() => currentStatus = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: assignedStaff,
                      decoration: const InputDecoration(labelText: 'Assigned Staff'),
                      items: [
                        'Ramesh (Electrician)',
                        'Suresh (Plumber)',
                        'Sunita (Housekeeping)',
                        'Kiran (Network Tech)',
                        'Manoj (Security)',
                      ].map((String s) {
                        return DropdownMenuItem(value: s, child: Text(s));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setStateModal(() => assignedStaff = val);
                      },
                    ),
                    Builder(builder: (context) {
                      final dynamicStaff = AppData.staff.isNotEmpty
                          ? AppData.staff.map((s) => '${s['name']} (${s['role'] ?? 'Staff'})').toList()
                          : [
                              'Ramesh (Electrician)',
                              'Suresh (Plumber)',
                              'Sunita (Housekeeping)',
                              'Kiran (Network Tech)',
                              'Manoj (Security)',
                            ];
                      if (!dynamicStaff.contains(assignedStaff)) {
                        dynamicStaff.insert(0, assignedStaff);
                      }
                      return DropdownButtonFormField<String>(
                        initialValue: assignedStaff,
                        decoration: const InputDecoration(labelText: 'Assigned Staff'),
                        items: dynamicStaff.map((String s) {
                          return DropdownMenuItem(value: s, child: Text(s));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setStateModal(() => assignedStaff = val);
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final compId = complaint['id']?.toString();
                    if (compId != null && compId.isNotEmpty && !compId.startsWith('CMP-')) {
                      try {
                        // Find staff ID if assigning
                        String? staffId;
                        for (var s in AppData.staff) {
                          if (assignedStaff.contains(s['name']?.toString() ?? '')) {
                            staffId = s['id']?.toString();
                            break;
                          }
                        }
                        if (staffId != null && !staffId.startsWith('staff-')) {
                          await AdminApiService.assignComplaint(compId, staffId);
                        }

                        if (currentStatus == 'Resolved') {
                          await AdminApiService.resolveComplaint(compId, notes: 'Resolved by admin');
                        } else {
                          await AdminApiService.updateComplaint(compId, {
                            'status': currentStatus == 'In Progress' ? 'IN_PROGRESS' : 'OPEN',
                          });
                        }
                        _loadComplaintsFromApi();
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to update complaint: $e'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }
                    }
                    if (!mounted) return;
                    setState(() {
                      complaint['status'] = currentStatus;
                      complaint['assigned_staff'] = assignedStaff;
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ticket updated to $currentStatus!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentStatus == 'Resolved' ? const Color(0xFF059669) : AppTheme.primaryBlue,
                  ),
                  child: Text(currentStatus == 'Resolved' ? 'Mark Resolved' : 'Save Changes'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
