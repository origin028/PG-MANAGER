import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/data/app_data.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/widgets/table_components.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Map<String, dynamic>> get _staff => AppData.staff;
  List<Map<String, dynamic>> get _employeeSalaries => AppData.employeeSalaries;
  int _selectedTab = 0; // 0: Staff Directory, 1: Salary Disbursements
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return PremiumDialog(
              maxWidth: 480,
              icon: Icons.person_add_alt_1_rounded,
              title: 'Add New Staff Member',
              subtitle: 'Assign staff designation, contact, and compensation',
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
                          if (nameController.text.trim().isEmpty || phoneController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please fill all required fields'), backgroundColor: AppTheme.statusRed),
                            );
                            return;
                          }

                          setModalState(() => isSubmitting = true);

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
                              setModalState(() => isSubmitting = false);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('Failed to add staff: $e'), backgroundColor: AppTheme.statusRed),
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
                              const SnackBar(content: Text('Staff Member Added!'), backgroundColor: AppTheme.successGreen),
                            );
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(isSubmitting ? 'Adding...' : 'Add Staff', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
                    hintText: 'e.g. Ramesh Kumar',
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: 'Role / Designation',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                                ),
                                children: const [
                                  TextSpan(text: ' *', style: TextStyle(color: AppTheme.statusRed, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: selectedRole,
                              isExpanded: true,
                              decoration: AppTheme.formDropdownDecoration(
                                fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                              ),
                              dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                              items: ['Warden', 'Housekeeping', 'Security', 'Cook', 'Manager'].map((String role) {
                                return DropdownMenuItem(value: role, child: Text(role));
                              }).toList(),
                              onChanged: (val) => selectedRole = val!,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: PremiumFormField(
                          label: 'Phone Number',
                          isRequired: true,
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          hintText: 'e.g. 9876543210',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PremiumFormField(
                    label: 'Monthly Salary (₹)',
                    controller: salaryController,
                    keyboardType: TextInputType.number,
                    hintText: 'e.g. 15000',
                    prefixText: '₹ ',
                    prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                  ),
                ],
              ),
            );
          },
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
    bool isSaving = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return PremiumDialog(
              maxWidth: 480,
              icon: Icons.badge_outlined,
              title: 'Edit Staff Details',
              subtitle: 'Update role assignment and salary record',
              actions: [
                OutlinedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final confirmed = await showPremiumConfirmDialog(
                            context: context,
                            title: 'Remove Staff Member?',
                            message: 'Are you sure you want to remove ${staffMember['name']} from staff records?',
                            confirmText: 'Remove Staff',
                            cancelText: 'Cancel',
                            icon: Icons.delete_outline_rounded,
                            isDestructive: true,
                          );

                          if (confirmed == true) {
                            final staffId = staffMember['id']?.toString();
                            if (staffId != null && staffId.isNotEmpty && !staffId.startsWith('staff-')) {
                              try {
                                await AdminApiService.deleteStaff(staffId);
                                _loadStaffFromApi();
                              } catch (e) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                                    SnackBar(content: Text('Failed to delete staff: $e'), backgroundColor: AppTheme.statusRed),
                                  );
                                }
                                return;
                              }
                            }
                            setState(() {
                              _staff.remove(staffMember);
                            });
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${staffMember['name']} removed!'),
                                  backgroundColor: AppTheme.statusRed,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.statusRed),
                  label: Text('Delete', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.statusRed)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.statusRed.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                    side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: isSaving
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

                          setModalState(() => isSaving = true);

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
                              setModalState(() => isSaving = false);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('Failed to update staff: $e'), backgroundColor: AppTheme.statusRed),
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
                              const SnackBar(content: Text('Staff details updated!'), backgroundColor: AppTheme.successGreen),
                            );
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(isSaving ? 'Saving...' : 'Save Changes', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
                  TextFormField(
                    controller: nameController,
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: AppTheme.formInputDecoration(
                      labelText: 'Full Name *',
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: 'Role / Designation',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                                ),
                                children: const [
                                  TextSpan(text: ' *', style: TextStyle(color: AppTheme.statusRed, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: selectedRole,
                              isExpanded: true,
                              decoration: AppTheme.formDropdownDecoration(
                                fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                              ),
                              dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                              items: allowedRoles.map((String role) {
                                return DropdownMenuItem(value: role, child: Text(role));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedRole = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: PremiumFormField(
                          label: 'Phone Number',
                          isRequired: true,
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          hintText: 'Phone Number',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PremiumFormField(
                    label: 'Monthly Salary (₹)',
                    controller: salaryController,
                    keyboardType: TextInputType.number,
                    hintText: 'Monthly Salary',
                    prefixText: '₹ ',
                    prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteStaff(Map<String, dynamic> staffMember) async {
    final confirmed = await showPremiumConfirmDialog(
      context: context,
      title: 'Delete Staff Member?',
      subtitle: 'This action may affect associated staff records.',
      message: 'Are you sure you want to delete ${staffMember['name']}? This action will permanently remove this staff profile.',
      confirmText: 'Delete Staff',
      cancelText: 'Cancel',
      icon: Icons.delete_forever_rounded,
      isDestructive: true,
      details: [
        {'label': 'Staff Name', 'value': staffMember['name'] ?? 'Staff Member'},
        {'label': 'Role', 'value': staffMember['role'] ?? 'Staff'},
        {'label': 'Phone', 'value': staffMember['phone'] ?? 'N/A'},
      ],
    );

    if (confirmed == true) {
      final staffId = staffMember['id']?.toString();
      if (staffId != null && staffId.isNotEmpty && !staffId.startsWith('staff-')) {
        try {
          await AdminApiService.deleteStaff(staffId);
          _loadStaffFromApi();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete staff: $e'), backgroundColor: AppTheme.statusRed),
            );
          }
          return;
        }
      }
      setState(() {
        _staff.remove(staffMember);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${staffMember['name']} deleted successfully!'),
            backgroundColor: AppTheme.statusOk,
          ),
        );
      }
    }
  }

  void _showAddSalaryDialog() {
    final nameController = TextEditingController();
    final roleController = TextEditingController();
    final amountController = TextEditingController();
    String selectedMonth = 'October 2026';
    String selectedProperty = AppData.selectedProperty;
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dynamicProps = AppData.propertyNames.isNotEmpty ? AppData.propertyNames : [selectedProperty];
            if (!dynamicProps.contains(selectedProperty)) {
              selectedProperty = dynamicProps.first;
            }

            return PremiumDialog(
              maxWidth: 500,
              icon: Icons.payments_rounded,
              title: 'Record Employee Salary',
              subtitle: 'Disburse monthly compensation to property staff',
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
                          final amt = int.tryParse(amountController.text.trim()) ?? 0;
                          if (name.isEmpty || amt <= 0) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please fill valid name and amount'), backgroundColor: AppTheme.statusRed),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          String? targetPropId;
                          for (var p in AppData.properties) {
                            if (p['name'] == selectedProperty) {
                              targetPropId = p['id']?.toString();
                              break;
                            }
                          }
                          targetPropId ??= AppData.selectedPropertyId;

                          String? createdSalaryId;
                          if (targetPropId != null && targetPropId.isNotEmpty && !targetPropId.startsWith('p')) {
                            try {
                              final created = await AdminApiService.createExpense({
                                'property_id': targetPropId,
                                'title': 'Salary: $name (${roleController.text.trim()}) - $selectedMonth',
                                'amount': amt.toDouble(),
                                'category': 'SALARY',
                                'method': 'BANK_TRANSFER',
                                'date': DateTime.now().toIso8601String().substring(0, 10),
                              });
                              if (created.isNotEmpty && created['id'] != null) {
                                createdSalaryId = created['id']?.toString();
                              }
                            } catch (e) {
                              debugPrint('API createExpense for salary error: $e');
                            }
                          }

                          setState(() {
                            AppData.employeeSalaries.insert(0, {
                              'id': createdSalaryId ?? 'sal-${DateTime.now().millisecondsSinceEpoch}',
                              'name': name,
                              'role': roleController.text.trim().isNotEmpty ? roleController.text.trim() : 'Staff',
                              'payment_date': DateTime.now().toIso8601String().substring(0, 10),
                              'salary_month': selectedMonth,
                              'amount': amt,
                              'property': selectedProperty,
                            });
                          });

                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Salary of ₹ $amt recorded for $name!'), backgroundColor: AppTheme.statusOk),
                            );
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(isSubmitting ? 'Recording...' : 'Record Salary', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: PremiumFormField(
                          label: 'Employee Name',
                          hintText: 'e.g. Ramesh Kumar',
                          controller: nameController,
                          prefixIcon: Icons.person_outline_rounded,
                          isRequired: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PremiumFormField(
                          label: 'Role / Designation',
                          hintText: 'e.g. Head Cook, Security',
                          controller: roleController,
                          prefixIcon: Icons.badge_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PremiumFormField(
                          label: 'Amount (₹)',
                          hintText: 'e.g. 15000',
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          prefixIcon: Icons.currency_rupee_rounded,
                          isRequired: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Property',
                              style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: selectedProperty,
                              isExpanded: true,
                              decoration: AppTheme.formDropdownDecoration(fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground),
                              dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                              icon: Icon(Icons.keyboard_arrow_down, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText),
                              items: dynamicProps.map((String prop) {
                                return DropdownMenuItem(value: prop, child: Text(prop, style: GoogleFonts.manrope(fontSize: 13), overflow: TextOverflow.ellipsis));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setDialogState(() => selectedProperty = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
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
    final totalStaff = _staff.length;
    final activeStaff = _staff.where((s) => s['status'] == 'Active').length;
    final totalDisbursed = _employeeSalaries.fold<int>(0, (sum, s) => sum + (int.tryParse(s['amount']?.toString() ?? '0') ?? 0));

    final filteredStaff = _staff.where((st) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return (st['name'] ?? '').toString().toLowerCase().contains(q) ||
          (st['role'] ?? '').toString().toLowerCase().contains(q) ||
          (st['phone'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    final filteredSalaries = _employeeSalaries.where((sal) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return (sal['name'] ?? '').toString().toLowerCase().contains(q) ||
          (sal['role'] ?? '').toString().toLowerCase().contains(q) ||
          (sal['salary_month'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: EdgeInsets.all(isNarrow ? 14.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final titleSection = const Text(
                'Staff Management',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              );

              final actionBtn = ElevatedButton.icon(
                onPressed: _selectedTab == 0 ? _showAddStaffDialog : _showAddSalaryDialog,
                icon: Icon(_selectedTab == 0 ? Icons.person_add_rounded : Icons.payments_rounded, size: 18),
                label: Text(_selectedTab == 0 ? 'Add Staff' : 'Record Salary'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(140, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    const SizedBox(height: 12),
                    actionBtn,
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  titleSection,
                  actionBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Tab Switcher: Staff Directory vs Salary Disbursements
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Staff Directory (${_staff.length})'),
                selected: _selectedTab == 0,
                onSelected: (_) => setState(() => _selectedTab = 0),
              ),
              ChoiceChip(
                label: Text('Salary Disbursements (${_employeeSalaries.length})'),
                selected: _selectedTab == 1,
                onSelected: (_) => setState(() => _selectedTab = 1),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // KPI Summary Cards
          if (_selectedTab == 0)
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
              ],
            )
          else
            TableKpiGrid(
              cards: [
                TableKpiCard(
                  title: 'Total Payroll Disbursed',
                  value: '₹ $totalDisbursed',
                  subtitle: 'Historical compensation paid',
                  icon: Icons.payments_outlined,
                  iconColor: const Color(0xFF059669),
                  iconBgColor: const Color(0xFFECFDF5),
                ),
                TableKpiCard(
                  title: 'Disbursement Entries',
                  value: '${_employeeSalaries.length}',
                  subtitle: 'Recorded payslips',
                  icon: Icons.receipt_long_outlined,
                  iconColor: const Color(0xFF2563EB),
                  iconBgColor: const Color(0xFFEFF6FF),
                ),
              ],
            ),
          const SizedBox(height: 18),

          // Search Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: _selectedTab == 0 ? 'Search staff by name, role, phone...' : 'Search salary records by name, role...',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textGrey),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Data Table
          Expanded(
            child: Container(
              decoration: modernTableDecoration,
              child: _selectedTab == 0
                  ? (_staff.isEmpty
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
                                    rows: filteredStaff.map((st) {
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
                                                icon: Icons.delete_outline_rounded,
                                                color: AppTheme.statusRed,
                                                onPressed: () => _confirmDeleteStaff(st),
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
                        ))
                  : (_employeeSalaries.isEmpty
                      ? EmptyState(
                          icon: Icons.payments_outlined,
                          title: 'No salary records yet',
                          subtitle: 'Record monthly salary disbursements for property staff',
                          actionLabel: 'Record Salary',
                          onAction: _showAddSalaryDialog,
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
                                    dataRowMinHeight: 60,
                                    dataRowMaxHeight: 68,
                                    columnSpacing: 24,
                                    horizontalMargin: 24,
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                    headingRowHeight: 48,
                                    dataRowColor: modernRowColor,
                                    border: const TableBorder(
                                      horizontalInside: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                                    ),
                                    columns: [
                                      modernTableColumn('EMPLOYEE NAME'),
                                      modernTableColumn('PAYMENT DATE'),
                                      modernTableColumn('SALARY MONTH'),
                                      modernTableColumn('AMOUNT'),
                                      modernTableColumn('PROPERTY'),
                                      modernTableColumn('ACTIONS'),
                                    ],
                                    rows: filteredSalaries.map((sal) {
                                      return DataRow(cells: [
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TableAvatar(name: sal['name'] ?? 'E', radius: 15),
                                              const SizedBox(width: 10),
                                              Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(sal['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                                                  if (sal['role'] != null)
                                                    Text(sal['role'], style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Text(sal['payment_date'] ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, fontWeight: FontWeight.w500)),
                                        ),
                                        DataCell(
                                          Text(sal['salary_month'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                                        ),
                                        DataCell(
                                          Text('₹ ${sal['amount']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                                        ),
                                        DataCell(
                                          Text(sal['property'] ?? 'Green View PG - Hebbal', style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
                                        ),
                                        DataCell(
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textGrey),
                                            tooltip: 'Actions',
                                            onSelected: (val) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Downloading payslip for ${sal['name']}...')),
                                              );
                                            },
                                            itemBuilder: (ctx) => [
                                              const PopupMenuItem(value: 'payslip', child: Text('Download Payslip', style: TextStyle(fontSize: 13))),
                                              const PopupMenuItem(value: 'details', child: Text('View Details', style: TextStyle(fontSize: 13))),
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
                        )),
            ),
          ),
        ],
      ),
    );
  }
}