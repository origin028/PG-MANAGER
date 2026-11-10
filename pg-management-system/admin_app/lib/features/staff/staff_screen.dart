import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/table_components.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Map<String, dynamic>> get _staff => AppData.staff;

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_loadStaffFromApi);
    _loadStaffFromApi();
  }

  void _loadStaffFromApi() async {
    final propId = AppData.selectedPropertyId;
    try {
      final list = await AdminApiService.getStaff(propertyId: propId);
      if (list.isNotEmpty && mounted) {
        setState(() {
          AppData.staff = list.map((s) => <String, dynamic>{
            'id': s['id']?.toString() ?? '',
            'name': s['full_name'] ?? s['name'] ?? 'Staff Member',
            'phone': s['phone'] ?? '',
            'role': s['role'] ?? 'Warden',
            'salary': (s['salary'] ?? 15000).toInt(),
            'status': s['is_active'] == false ? 'Inactive' : 'Active',
            'property': s['property_name'] ?? AppData.selectedProperty,
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('API getStaff error: $e');
    }
  }

  IconData _getRoleIcon(String? role) {
    switch (role?.toLowerCase()) {
      case 'security':
        return Icons.security;
      case 'housekeeping':
        return Icons.cleaning_services_outlined;
      case 'warden':
        return Icons.admin_panel_settings_outlined;
      case 'cook':
        return Icons.restaurant_outlined;
      case 'manager':
        return Icons.manage_accounts_outlined;
      default:
        return Icons.person_outline;
    }
  }

  void _showAddStaffDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final salaryController = TextEditingController();
    String selectedRole = 'Warden';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: const Text('Add New Staff'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(hintText: 'Full Name'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(hintText: 'Role'),
                        items: ['Warden', 'Housekeeping', 'Security', 'Cook', 'Manager'].map((String role) {
                          return DropdownMenuItem(value: role, child: Text(role));
                        }).toList(),
                        onChanged: (val) => selectedRole = val!,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: 'Phone Number'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: salaryController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Monthly Salary', prefixText: '₹ '),
                ),
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
                if (nameController.text.isEmpty || phoneController.text.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final propId = AppData.selectedPropertyId;
                String? createdStaffId;
                if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                  try {
                    final created = await AdminApiService.createStaff({
                      'property_id': propId,
                      'name': nameController.text.trim(),
                      'role': selectedRole.toUpperCase(),
                      'phone': phoneController.text.trim(),
                      'salary': double.tryParse(salaryController.text.trim()) ?? 15000.0,
                      'joining_date': DateTime.now().toIso8601String().substring(0, 10),
                    });
                    if (created.isNotEmpty && created['id'] != null) {
                      createdStaffId = created['id'].toString();
                    }
                    _loadStaffFromApi();
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Failed to add staff: $e'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }
                }

                final newStaff = <String, dynamic>{
                  'name': nameController.text.trim(),
                  'role': selectedRole,
                  'phone': phoneController.text.trim(),
                  'salary': salaryController.text.isEmpty ? '0' : salaryController.text.trim(),
                  'status': 'Active',
                };
                if (createdStaffId != null) {
                  newStaff['id'] = createdStaffId;
                }

                if (!mounted) return;
                setState(() {
                  _staff.insert(0, newStaff);
                });

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Staff Member Added!'), backgroundColor: Colors.green),
                  );
                }
              },
              child: const Text('Add Staff'),
            ),
          ],
        );
      },
    );
  }

  void _showEditStaffDialog(Map<String, dynamic> staffMember) {
    final nameController = TextEditingController(text: staffMember['name']?.toString() ?? '');
    final phoneController = TextEditingController(text: staffMember['phone']?.toString() ?? '');
    final salaryController = TextEditingController(text: staffMember['salary']?.toString() ?? '');
    final allowedRoles = ['Warden', 'Housekeeping', 'Security', 'Cook', 'Manager'];
    String currentRole = staffMember['role']?.toString() ?? 'Warden';
    if (!allowedRoles.contains(currentRole)) {
      allowedRoles.add(currentRole);
    }
    String selectedRole = currentRole;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: const Text('Edit Staff Details'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(hintText: 'Full Name', labelText: 'Full Name *'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            decoration: const InputDecoration(hintText: 'Role', labelText: 'Role *'),
                            items: allowedRoles.map((String role) {
                              return DropdownMenuItem(value: role, child: Text(role));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setModalState(() => selectedRole = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(hintText: 'Phone Number', labelText: 'Phone *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: salaryController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Monthly Salary',
                        labelText: 'Monthly Salary',
                        prefixText: '₹ ',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final staffId = staffMember['id']?.toString();
                        if (staffId != null && staffId.isNotEmpty && !staffId.startsWith('staff-')) {
                          try {
                            await AdminApiService.deleteStaff(staffId);
                            _loadStaffFromApi();
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('Failed to delete staff: $e'), backgroundColor: Colors.red),
                              );
                            }
                            return;
                          }
                        }
                        setState(() {
                          _staff.remove(staffMember);
                        });
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${staffMember['name']} removed!'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            final phone = phoneController.text.trim();
                            if (name.isEmpty || phone.isEmpty) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.red),
                              );
                              return;
                            }

                            final staffId = staffMember['id']?.toString();
                            if (staffId != null && staffId.isNotEmpty && !staffId.startsWith('staff-')) {
                              try {
                                await AdminApiService.updateStaff(staffId, {
                                  'name': name,
                                  'role': selectedRole.toUpperCase(),
                                  'phone': phone,
                                  'salary': double.tryParse(salaryController.text.trim()) ?? 15000.0,
                                });
                                _loadStaffFromApi();
                              } catch (e) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                                    SnackBar(content: Text('Failed to update staff: $e'), backgroundColor: Colors.red),
                                  );
                                }
                                return;
                              }
                            }

                            if (!mounted) return;
                            setState(() {
                              staffMember['name'] = name;
                              staffMember['role'] = selectedRole;
                              staffMember['phone'] = phone;
                              staffMember['salary'] = salaryController.text.trim().isEmpty ? '0' : salaryController.text.trim();
                            });

                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Staff details updated!'), backgroundColor: Colors.green),
                              );
                            }
                          },
                          child: const Text('Save Changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalStaff = _staff.length;
    final activeStaff = _staff.where((s) => s['status'] == 'Active').length;
    final onLeaveStaff = _staff.where((s) => s['status'] == 'On Leave').length;
    final totalPayroll = _staff.fold<int>(0, (sum, s) => sum + (int.tryParse(s['salary']?.toString() ?? '0') ?? 0));

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final titleSection = const Text('Staff Management', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark));

              final addBtn = ElevatedButton.icon(
                onPressed: _showAddStaffDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Staff'),
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
                title: 'Total Staff',
                value: '$totalStaff',
                subtitle: 'All departments',
                icon: Icons.badge_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
              ),
              TableKpiCard(
                title: 'Active on Duty',
                value: '$activeStaff',
                subtitle: 'Present today',
                icon: Icons.verified_user_outlined,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              ),
              TableKpiCard(
                title: 'On Leave',
                value: '$onLeaveStaff',
                subtitle: 'Approved leave',
                icon: Icons.beach_access_outlined,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFFFBEB),
              ),
              TableKpiCard(
                title: 'Monthly Payroll',
                value: '₹ $totalPayroll',
                subtitle: 'Estimated cost',
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFF7C3AED),
                iconBgColor: const Color(0xFFF5F3FF),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Data Table
          Expanded(
            child: Container(
              decoration: modernTableDecoration,
              child: _staff.isEmpty
                  ? EmptyState(
                      icon: Icons.badge_outlined,
                      title: 'No staff members yet',
                      subtitle: 'Add wardens, security, and housekeeping staff here',
                      actionLabel: 'Add Staff',
                      onAction: _showAddStaffDialog,
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
                                  modernTableColumn('Staff Member'),
                                  modernTableColumn('Role'),
                                  modernTableColumn('Phone Number'),
                                  modernTableColumn('Monthly Salary'),
                                  modernTableColumn('Status'),
                                  modernTableColumn('Actions'),
                                ],
                                rows: _staff.map((st) {
                                  return DataRow(cells: [
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableAvatar(name: st['name'] ?? 'S', radius: 18),
                                          const SizedBox(width: 12),
                                          Text(
                                            st['name'], 
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(_getRoleIcon(st['role']), size: 16, color: AppTheme.primaryBlue),
                                          const SizedBox(width: 8),
                                          Text(
                                            st['role'],
                                            style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        st['phone'],
                                        style: const TextStyle(color: AppTheme.textGrey, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '₹ ${st['salary']}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 14),
                                      ),
                                    ),
                                    DataCell(
                                      StatusPill(status: st['status']),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableActionIconButton(
                                            tooltip: 'Edit Staff',
                                            icon: Icons.edit_outlined,
                                            onPressed: () => _showEditStaffDialog(st),
                                          ),
                                          const SizedBox(width: 6),
                                          TableActionIconButton(
                                            tooltip: 'Delete Staff',
                                            icon: Icons.delete_outline,
                                            color: Colors.red.shade400,
                                            onPressed: () {
                                              setState(() {
                                                _staff.removeWhere((s) => s['name'] == st['name']);
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('${st['name']} removed!'), backgroundColor: Colors.orange),
                                              );
                                            },
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