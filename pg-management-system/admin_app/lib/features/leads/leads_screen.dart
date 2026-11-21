import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/data/app_data.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/premium_dialogs.dart';
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
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return PremiumDialog(
              maxWidth: 460,
              icon: Icons.person_add_rounded,
              title: 'Add New Lead',
              subtitle: 'Capture inquiry from prospective resident',
              actions: [
                OutlinedButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
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
                          final name = nameController.text.trim();
                          final phone = phoneController.text.trim();
                          if (name.isEmpty || phone.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please fill all required fields'), backgroundColor: AppTheme.statusRed),
                            );
                            return;
                          }

                          setModalState(() => isSubmitting = true);

                          final propId = AppData.selectedPropertyId;
                          String? createdLeadId;
                          if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
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
                              _loadLeadsFromApi();
                            } catch (e) {
                              setModalState(() => isSubmitting = false);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('Failed to save lead: $e'), backgroundColor: AppTheme.statusRed),
                                );
                              }
                              return;
                            }
                          }

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
                          setState(() {
                            _leads.insert(0, newLead);
                          });

                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lead added successfully!'), backgroundColor: AppTheme.successGreen),
                            );
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(isSubmitting ? 'Saving...' : 'Save Lead', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
                  PremiumFormField(
                    label: 'Full Name',
                    isRequired: true,
                    controller: nameController,
                    hintText: 'e.g. Rahul Sharma',
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                  ),
                  const SizedBox(height: 16),
                  PremiumFormField(
                    label: 'Phone Number',
                    isRequired: true,
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    hintText: 'e.g. 9876543210',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Lead Source',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSource,
                    decoration: AppTheme.formDropdownDecoration(
                      fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                    ),
                    dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                    items: ['Walk-in', 'Instagram', 'Referral', 'MagicBricks', 'Other'].map((String src) {
                      return DropdownMenuItem(value: src, child: Text(src, style: GoogleFonts.manrope(fontSize: 13)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedSource = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pipeline Status',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: AppTheme.formDropdownDecoration(
                      fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                    ).copyWith(
                      labelText: 'Status',
                    ),
                    dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                    items: statusOptions.map((String stat) {
                      return DropdownMenuItem(value: stat, child: Text(stat, style: GoogleFonts.manrope(fontSize: 13)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedStatus = val);
                    },
                  ),
                ],
              ),
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
    final propertyId = lead['property_id']?.toString() ?? AppData.selectedPropertyId ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showPremiumConfirmDialog(
      context: context,
      title: 'Convert to Resident',
      message: 'Convert $leadName from a sales inquiry into an onboarded resident record.',
      confirmText: 'Convert Now',
      cancelText: 'Cancel',
      icon: Icons.how_to_reg_rounded,
      type: PremiumDialogType.success,
      detailsWidget: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.person_rounded, size: 16, color: AppTheme.primaryTeal),
                const SizedBox(width: 8),
                Text('Name: ', style: GoogleFonts.manrope(fontSize: 13, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText)),
                Text(leadName, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_rounded, size: 16, color: AppTheme.primaryTeal),
                const SizedBox(width: 8),
                Text('Phone: ', style: GoogleFonts.manrope(fontSize: 13, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText)),
                Text(leadPhone, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText)),
              ],
            ),
            if (leadEmail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.email_rounded, size: 16, color: AppTheme.primaryTeal),
                  const SizedBox(width: 8),
                  Text('Email: ', style: GoogleFonts.manrope(fontSize: 13, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText)),
                  Text(leadEmail, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText)),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final leadId = lead['id']?.toString();
      if (leadId != null && leadId.isNotEmpty && !leadId.startsWith('lead-')) {
        try {
          await AdminApiService.convertLead(leadId, {
            if (propertyId.isNotEmpty) 'property_id': propertyId,
            'monthly_rent': 6000.0,
            'security_deposit': 6000.0,
          });
          _loadLeadsFromApi();
        } catch (e) {
          debugPrint('Error updating lead status: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lead conversion failed: $e'), backgroundColor: Colors.red),
            );
          }
          return;
        }
      }
      setState(() {
        lead['status'] = 'Converted';
      });

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

      if (mounted) {
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

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return PremiumDialog(
              maxWidth: 440,
              icon: Icons.edit_note_rounded,
              title: 'Update Lead Status',
              subtitle: 'Prospect: ${lead['name']} • ${lead['phone']}',
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
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
                        backgroundColor: AppTheme.successGreen,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text('Save Status', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
                    'Pipeline Status *',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: AppTheme.formDropdownDecoration(
                      labelText: 'Select Status',
                      prefixIcon: const Icon(Icons.flag_outlined, size: 20, color: AppTheme.secondaryText),
                      fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
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
                ],
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

    return SingleChildScrollView(
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
          Container(
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
        ],
      ),
    );
  }
}