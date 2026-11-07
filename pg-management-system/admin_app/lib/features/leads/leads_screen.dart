import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/table_components.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  // Shared Leads from AppData (persists across navigation)
  List<Map<String, dynamic>> get _leads => AppData.leads;

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_loadLeadsFromApi);
    _loadLeadsFromApi();
  }

  void _loadLeadsFromApi() async {
    final propId = AppData.selectedPropertyId;
    try {
      final list = await AdminApiService.getLeads(propertyId: propId);
      if (list.isNotEmpty && mounted) {
        setState(() {
          AppData.leads = list.map((l) => <String, dynamic>{
            'id': l['id']?.toString() ?? '',
            'name': l['name'] ?? 'Lead',
            'phone': l['phone'] ?? '',
            'source': l['source'] ?? 'Walk-in',
            'status': l['status'] ?? 'New',
            'date': l['created_at']?.toString().substring(0, 10) ?? '2026-10-18',
            'property': l['property_name'] ?? AppData.selectedProperty,
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('API getLeads error: $e');
    }
  }

  IconData _getSourceIcon(String? source) {
    switch (source?.toLowerCase()) {
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'walk-in':
        return Icons.directions_walk;
      case 'referral':
        return Icons.people_outline;
      case 'magicbricks':
        return Icons.apartment;
      default:
        return Icons.language;
    }
  }

  void _showAddLeadDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedSource = 'Walk-in';
    String selectedStatus = 'New';
    const statusOptions = ['New', 'Contacted', 'Visit Scheduled', 'Converted', 'Lost'];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
          builder: (context, setModalState) {
          builder: (modalCtx, setModalState) {
              title: const Text('Add New Lead'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g. Rahul Sharma'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number', hintText: 'e.g. 9876543210'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSource,
                        decoration: const InputDecoration(labelText: 'Source'),
                        items: ['Walk-in', 'Instagram', 'Referral', 'MagicBricks', 'Other'].map((String src) {
                          return DropdownMenuItem(value: src, child: Text(src));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedSource = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: statusOptions.map((String stat) {
                          return DropdownMenuItem(value: stat, child: Text(stat));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedStatus = val);
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
                  onPressed: () {
                  onPressed: () async {
                    final phone = phoneController.text.trim();
                    if (name.isEmpty || phone.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final propId = AppData.selectedPropertyId;
                    if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                    String? createdLeadId;
                      AdminApiService.createLead({
                      AdminApiService.createLead({
                        'property_id': propId,
                        'name': name,
                        'phone': phone,
                        'source': selectedSource.toUpperCase().replaceAll('-', '_'),
                        'status': selectedStatus.toUpperCase().replaceAll(' ', '_'),
                      }).then((_) {
                      try {
                        final created = await AdminApiService.createLead({
                          'property_id': propId,
                          'name': name,
                          'phone': phone,
                          'source': selectedSource.toUpperCase().replaceAll('-', '_'),
                          'status': selectedStatus.toUpperCase().replaceAll(' ', '_'),
                        });
                        if (created.isNotEmpty && created['id'] != null) {
                          createdLeadId = created['id'].toString();
                        }
                      }).catchError((e) {
                      }).catchError((e) {
                        debugPrint('API createLead error: $e');
                      });
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to save lead: $e'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }

                    setState(() {
                    final newLead = <String, dynamic>{
                      'name': name,
                      'phone': phone,
                      'source': selectedSource,
                      'status': selectedStatus,
                      'date': 'Today',
                    };
                    if (createdLeadId != null) {
                      newLead['id'] = createdLeadId;
                    }

                    if (!mounted) return;
                      _leads.insert(0, {
                      _leads.insert(0, {
                        'name': name,
                        'phone': phone,
                        'source': selectedSource,
                        'status': selectedStatus,
                        'date': 'Today',
                      });
                      _leads.insert(0, newLead);

                    final messenger = ScaffoldMessenger.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                    );
                  },
                  child: const Text('Save Lead'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _convertLeadToResident(Map<String, dynamic> lead) async {
    final leadName = lead['name']?.toString() ?? 'Prospect';
    final leadPhone = lead['phone']?.toString() ?? '';
    final leadEmail = lead['email']?.toString() ?? '';
    final propertyId = lead['property_id']?.toString() ?? '';
    final propertyId = lead['property_id']?.toString() ?? '';
    final propertyId = lead['property_id']?.toString() ?? AppData.selectedPropertyId ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Convert $leadName to Resident'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Convert this prospect into an onboarded resident record with prefilled details:'),
            const SizedBox(height: 12),
            Text('Name: $leadName', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Phone: $leadPhone'),
            if (leadEmail.isNotEmpty) Text('Email: $leadEmail'),
            const SizedBox(height: 12),
            const Text('The lead status will automatically be updated to Converted in CRM.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert Now'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final leadId = lead['id']?.toString();
      if (leadId != null && leadId.isNotEmpty) {
      if (leadId != null && leadId.isNotEmpty) {
      if (leadId != null && leadId.isNotEmpty && !leadId.startsWith('lead-')) {
          await AdminApiService.updateLead(leadId, {'status': 'CONVERTED'});
          await AdminApiService.updateLead(leadId, {'status': 'CONVERTED'});
          await AdminApiService.convertLead(leadId, {
            if (propertyId.isNotEmpty) 'property_id': propertyId,
            'monthly_rent': 6000.0,
            'security_deposit': 6000.0,
          });
          _loadLeadsFromApi();
          debugPrint('Error updating lead status: $e');
          debugPrint('Error updating lead status: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lead conversion failed: $e'), backgroundColor: Colors.red),
            );
          }
          return;
      }
      setState(() {

        lead['status'] = 'Converted';
      });

      try {
      try {
        await AdminApiService.onboardResident({
          'name': leadName,
          'phone': leadPhone,
          'email': leadEmail,
          if (propertyId.isNotEmpty) 'property_id': propertyId,
          'rent_amount': 6000.0,
          'security_deposit': 6000.0,
        });
      } catch (e) {
        debugPrint('Resident onboard bridge info: $e');
      }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$leadName converted to Resident successfully!'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    }
  }

  void _showEditLeadStatusDialog(Map<String, dynamic> lead) {
    String selectedStatus = lead['status'] ?? 'New';
    const statuses = [
      'New',
      'Contacted',
      'Visit Scheduled',
      'Converted',
      'Lost',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
          builder: (context, setModalState) {
          builder: (modalCtx, setModalState) {
            final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final textPri = isDark ? Colors.white : AppTheme.textDark;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: cardBg,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with Prospect text aligned perfectly below title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryBlue, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Update Lead Status',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textPri,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Prospect: ${lead['name']} • ${lead['phone']}',
                                  style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
                            onPressed: () => Navigator.pop(dialogContext),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Pipeline Status Dropdown
                      const Text(
                        'Pipeline Status *',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: AppTheme.formDropdownDecoration(
                          labelText: 'Select Status',
                          prefixIcon: const Icon(Icons.flag_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: Colors.white,
                        items: statuses.map((String s) {
                          return DropdownMenuItem<String>(
                            value: s,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusPill(status: s),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedStatus = val);
                        },
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF374151),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              final leadId = lead['id']?.toString();
                              if (leadId != null && leadId.isNotEmpty && !leadId.startsWith('lead-')) {
                                AdminApiService.updateLead(leadId, {
                                  'status': selectedStatus.toUpperCase().replaceAll(' ', '_'),
                                }).then((_) {
                                  _loadLeadsFromApi();
                                }).catchError((e) {
                                  debugPrint('API updateLead error: $e');
                                });
                              }
                              setState(() {
                                lead['status'] = selectedStatus;
                              });
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Status for ${lead['name']} updated to "$selectedStatus"!'),
                                  backgroundColor: const Color(0xFF16A34A),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: const Text('Save Status', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
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

  @override
  Widget build(BuildContext context) {
    final totalLeads = _leads.length;
    final convertedCount = _leads.where((l) => l['status'] == 'Converted').length;
    final activeEnquiries = _leads.where((l) => l['status'] != 'Lost').length;
    final lostCount = _leads.where((l) => l['status'] == 'Lost').length;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final titleSection = const Text('Leads & Enquiries', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark));

              final addBtn = ElevatedButton.icon(
                onPressed: _showAddLeadDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Lead'),
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
                title: 'Total Leads',
                value: '$totalLeads',
                subtitle: 'All channels',
                icon: Icons.contact_mail_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
              ),
              TableKpiCard(
                title: 'Active Inquiries',
                value: '$activeEnquiries',
                subtitle: 'In follow-up pipeline',
                icon: Icons.calendar_today_outlined,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFFFBEB),
              ),
              TableKpiCard(
                title: 'Converted',
                value: '$convertedCount',
                subtitle: 'Moved into PG',
                icon: Icons.how_to_reg_outlined,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              ),
              TableKpiCard(
                title: 'Lost / Closed',
                value: '$lostCount',
                subtitle: 'Did not join',
                icon: Icons.person_off_outlined,
                iconColor: const Color(0xFFDC2626),
                iconBgColor: const Color(0xFFFEF2F2),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Data Table
          Expanded(
            child: Container(
              decoration: modernTableDecoration,
              child: _leads.isEmpty
                  ? EmptyState(
                      icon: Icons.trending_up,
                      title: 'No leads yet',
                      subtitle: 'Record walk-ins and inquiries to convert them into residents',
                      actionLabel: 'Add Lead',
                      onAction: _showAddLeadDialog,
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
                                dataRowMaxHeight: 70,
                                columnSpacing: 24,
                                horizontalMargin: 24,
                                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                headingRowHeight: 48,
                                dataRowColor: modernRowColor,
                                border: const TableBorder(
                                  horizontalInside: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                                ),
                                columns: [
                                  modernTableColumn('Prospect Name'),
                                  modernTableColumn('Phone Number'),
                                  modernTableColumn('Source'),
                                  modernTableColumn('Status'),
                                  modernTableColumn('Date Added'),
                                  modernTableColumn('Actions'),
                                ],
                                rows: _leads.map((lead) {
                                  return DataRow(cells: [
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableAvatar(name: lead['name'] ?? 'L', radius: 18),
                                          const SizedBox(width: 12),
                                          Text(
                                            lead['name'], 
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        lead['phone'],
                                        style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(_getSourceIcon(lead['source']), size: 16, color: AppTheme.primaryBlue),
                                          const SizedBox(width: 8),
                                          Text(
                                            lead['source'],
                                            style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      StatusPill(status: lead['status']),
                                    ),
                                    DataCell(
                                      Text(
                                        lead['date'],
                                        style: const TextStyle(color: AppTheme.textGrey, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableActionIconButton(
                                            tooltip: 'Call Prospect',
                                            icon: Icons.phone_outlined,
                                            color: const Color(0xFF059669),
                                            onPressed: () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Calling ${lead['name']} (${lead['phone']})...')),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 6),
                                          TableActionIconButton(
                                            tooltip: 'Edit Status',
                                            icon: Icons.edit_outlined,
                                            color: AppTheme.primaryBlue,
                                            onPressed: () => _showEditLeadStatusDialog(lead),
                                          ),
                                          const SizedBox(width: 6),
                                          TableActionIconButton(
                                            tooltip: 'Convert to Resident',
                                            icon: Icons.person_add_alt_1_outlined,
                                            color: const Color(0xFF059669),
                                            onPressed: () => _convertLeadToResident(lead),
                                          ),
                                        ],
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
}