import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/table_components.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/widgets/month_year_selector.dart';

class ResidentsScreen extends StatefulWidget {
  const ResidentsScreen({super.key});

  @override
  State<ResidentsScreen> createState() => _ResidentsScreenState();

  // Public static method to show Add Resident Dialog from anywhere (e.g. Bed Manager)
  static void showAddResidentDialog(
    BuildContext context, {
    String? prefilledRoom,
    String? prefilledFloor,
    VoidCallback? onComplete,
  }) {
    final nameController = TextEditingController();
    final dobController = TextEditingController();
    String gender = 'Male';
    final occupationController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final emergencyContactController = TextEditingController();
    final roomController = TextEditingController(text: prefilledRoom ?? '');

    String initialFloor = prefilledFloor ?? '';
    if (initialFloor.isEmpty && prefilledRoom != null && prefilledRoom.isNotEmpty) {
      final clean = prefilledRoom.trim().toLowerCase();
      final rMatch = AppData.rooms.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r?['number']?.toString().trim().toLowerCase() == clean,
        orElse: () => null,
      );
      if (rMatch != null && rMatch['floor'] != null) {
        initialFloor = rMatch['floor'].toString();
      }
    }
    final floorController = TextEditingController(text: initialFloor);
    final rentController = TextEditingController(text: '8000');
    final depositController = TextEditingController(text: '16000');
    final addressController = TextEditingController();
    final pincodeController = TextEditingController();
    final aadhaarController = TextEditingController();
    final panController = TextEditingController();

    String? localError;

    void autoPopulateFloor(String roomVal) {
      final clean = roomVal.trim();
      if (clean.isEmpty) return;
      final rMatch = AppData.rooms.cast<Map<String, dynamic>?>().firstWhere(
        (r) => r?['number']?.toString().trim().toLowerCase() == clean.toLowerCase(),
        orElse: () => null,
      );
      if (rMatch != null && rMatch['floor'] != null) {
        floorController.text = rMatch['floor'].toString();
      } else {
        final cleanDigits = clean.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanDigits.isNotEmpty) {
          floorController.text = cleanDigits.startsWith('2')
              ? '1st Floor'
              : (cleanDigits.startsWith('3')
                  ? '2nd Floor'
                  : (cleanDigits.startsWith('4') ? '3rd Floor' : 'Ground Floor'));
        }
      }
    }

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setModalState) {
            return PremiumDialog(
              maxWidth: 640,
              title: 'Onboard New Resident',
              subtitle: 'Enter personal, contact, stay and KYC details',
              icon: Icons.person_add_alt_1_rounded,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    String name = nameController.text.trim();
                    String phone = phoneController.text.trim();
                    String roomNo = roomController.text.trim();

                    if (name.isEmpty || phone.isEmpty || roomNo.isEmpty) {
                      setModalState(() {
                        localError = 'Name, Phone and Room Number are strictly required!';
                      });
                      return;
                    }

                    // Check for duplicate name
                    if (AppData.getResidentByName(name) != null) {
                      setModalState(() {
                        localError = 'Error: A resident named "$name" is already registered!';
                      });
                      return;
                    }

                    // Allocate next available bed in this room
                    AppData.assignResidentToRoom(
                      roomNo,
                      name,
                      phone: phone,
                      rent: int.tryParse(rentController.text) ?? 8000,
                      deposit: int.tryParse(depositController.text) ?? 16000,
                    );
                    final foundResident = AppData.getResidentByName(name);
                    final assignedBedName = foundResident?['bed']?.toString() ?? 'Bed A';

                    // API Call
                    final propId = AppData.selectedPropertyId;
                    String? backendResidentId;
                    if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                      try {
                        final created = await AdminApiService.onboardResident({
                          'property_id': propId,
                          'full_name': name,
                          'phone': phone,
                          'email': emailController.text.trim(),
                          'emergency_contact_phone': emergencyContactController.text.trim(),
                          'date_of_birth': dobController.text.trim(),
                          'gender': gender.toUpperCase(),
                          'occupation': occupationController.text.trim(),
                          'permanent_address': addressController.text.trim(),
                          'monthly_rent': double.tryParse(rentController.text) ?? 8000,
                          'security_deposit': double.tryParse(depositController.text) ?? 16000,
                        });
                        if (created.isNotEmpty && created['id'] != null) {
                          backendResidentId = created['id'].toString();
                        }
                      } catch (e) {
                        debugPrint('Could not sync resident to backend: $e');
                      }
                    }

                    final newResident = <String, dynamic>{
                      'name': name,
                      'phone': phone,
                      'email': emailController.text.trim().isNotEmpty ? emailController.text.trim() : '$name@example.com',
                      'emergency_contact': emergencyContactController.text.trim().isNotEmpty
                          ? emergencyContactController.text.trim()
                          : '9876543299',
                      'room': roomNo,
                      'floor': floorController.text.trim().isNotEmpty ? floorController.text.trim() : '1st Floor',
                      'bed': assignedBedName,
                      'rent': int.tryParse(rentController.text) ?? 8000,
                      'deposit': int.tryParse(depositController.text) ?? 16000,
                      'status': 'Active',
                      'kyc': 'Verified',
                      'dob': dobController.text.trim().isNotEmpty ? dobController.text.trim() : '01/01/2000',
                      'gender': gender,
                      'occupation': occupationController.text.trim().isNotEmpty
                          ? occupationController.text.trim()
                          : 'Professional',
                      'address': addressController.text.trim().isNotEmpty
                          ? addressController.text.trim()
                          : 'Bengaluru, Karnataka',
                      'pincode': pincodeController.text.trim().isNotEmpty ? pincodeController.text.trim() : '560001',
                      'aadhaar_number':
                          aadhaarController.text.trim().isNotEmpty ? aadhaarController.text.trim() : 'Not provided',
                      'pan_number': panController.text.trim().isNotEmpty ? panController.text.trim() : 'Not provided',
                      'property_name': AppData.selectedProperty,
                      'joining_date': 'Today',
                      'role': 'Resident',
                    };
                    if (backendResidentId != null) {
                      newResident['id'] = backendResidentId;
                    }

                    AppData.residents.insert(0, newResident);

                    // Auto-generate invoice
                    AppData.invoices.insert(0, {
                      'id': 'INV-2026-${100 + AppData.invoices.length}',
                      'name': name,
                      'room': roomNo,
                      'amount': int.tryParse(rentController.text) ?? 8000,
                      'status': 'Pending',
                      'date': 'Today',
                    });

                    AppData.saveResidentsToStorage();

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    onComplete?.call();

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Resident $name onboarded to Room $roomNo ($assignedBedName)!'),
                          backgroundColor: AppTheme.statusOk,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Onboard Resident'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                      if (localError != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  localError!,
                                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Section 1: Personal Details
                      _buildFormSectionHeader('Personal Information'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. Priya Sharma',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.person_outline, size: 20, color: AppTheme.textGrey),
                        ),
                        onChanged: (_) {
                          if (localError != null) setModalState(() => localError = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: dobController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Date of Birth',
                                labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                                hintText: 'DD/MM/YYYY',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                suffixIcon: Icon(Icons.calendar_month_outlined, size: 20, color: AppTheme.textGrey),
                              ),
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(2000, 1, 1),
                                  firstDate: DateTime(1960),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setModalState(() {
                                    dobController.text =
                                        "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: gender,
                              isExpanded: true,
                              decoration: AppTheme.formDropdownDecoration(labelText: 'Gender'),
                              borderRadius: BorderRadius.circular(12),
                              elevation: 2,
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                              items: ['Male', 'Female', 'Other'].map((g) {
                                return DropdownMenuItem(value: g, child: Text(g));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => gender = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: occupationController,
                        decoration: const InputDecoration(
                          labelText: 'Occupation',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. Software Engineer',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.work_outline, size: 20, color: AppTheme.textGrey),
                        ),
                      ),

                      const SizedBox(height: 20),
                      // Section 2: Contact
                      _buildFormSectionHeader('Contact Information'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. 9876543210',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.phone_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. resident@example.com',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.email_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emergencyContactController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Emergency Contact',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. 9876543299',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.contact_phone_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),

                      const SizedBox(height: 20),
                      // Section 3: Stay Information
                      _buildFormSectionHeader('Stay Information'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: roomController,
                              decoration: const InputDecoration(
                                labelText: 'Room Number *',
                                labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                                hintText: 'e.g. 101, 102, 201',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                prefixIcon: Icon(Icons.hotel_outlined, size: 20, color: AppTheme.textGrey),
                              ),
                              onChanged: (val) {
                                if (localError != null) setModalState(() => localError = null);
                                if (floorController.text.isEmpty) {
                                  autoPopulateFloor(val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: floorController,
                              decoration: const InputDecoration(
                                labelText: 'Floor Number',
                                labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                                hintText: 'e.g. Ground Floor, 1st Floor',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                prefixIcon: Icon(Icons.layers_outlined, size: 20, color: AppTheme.textGrey),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: rentController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Monthly Rent',
                                labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                                hintText: 'e.g. 8000',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                prefixText: '₹ ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: depositController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Security Deposit',
                                labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                                hintText: 'e.g. 16000',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                prefixText: '₹ ',
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      // Section 4: Address
                      _buildFormSectionHeader('Address'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Permanent Address',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'Door No, Street, City, State',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.location_on_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pincodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pincode',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. 560038',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.pin_drop_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),

                      const SizedBox(height: 20),
                      // Section 5: Documents
                      _buildFormSectionHeader('Identity Documents'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: aadhaarController,
                        decoration: const InputDecoration(
                          labelText: 'Aadhaar Number',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. 4512 8923 7104',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.badge_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: panController,
                        decoration: const InputDecoration(
                          labelText: 'PAN Number',
                          labelStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                          hintText: 'e.g. ABCPS1234F',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: Icon(Icons.credit_card_outlined, size: 20, color: AppTheme.textGrey),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      }

  // Public static method to show Edit Resident Dialog from anywhere
  static void showEditResidentDialog(
    BuildContext context,
    Map<String, dynamic> resident, {
    VoidCallback? onComplete,
  }) {
    final nameController = TextEditingController(text: resident['name'] ?? resident['full_name'] ?? '');
    final phoneController = TextEditingController(text: resident['phone'] ?? '');
    final emailController = TextEditingController(text: resident['email'] ?? '');
    final emergencyController = TextEditingController(text: resident['emergency_contact'] ?? resident['emergency_contact_phone'] ?? '');
    final dobController = TextEditingController(text: resident['dob'] ?? resident['date_of_birth']?.toString() ?? '');
    final occupationController = TextEditingController(text: resident['occupation'] ?? '');
    final addressController = TextEditingController(text: resident['address'] ?? resident['permanent_address'] ?? '');
    final pincodeController = TextEditingController(text: resident['pincode'] ?? '');
    final rentController = TextEditingController(text: (resident['rent'] ?? resident['monthly_rent'] ?? 8000).toString());
    final depositController = TextEditingController(text: (resident['deposit'] ?? resident['security_deposit'] ?? 16000).toString());

    String selectedGender = resident['gender'] ?? 'Male';
    if (!['Male', 'Female', 'Other'].contains(selectedGender)) {
      selectedGender = 'Male';
    }

    String selectedStatus = resident['status'] ?? 'Active';
    final validStatuses = ['Active', 'Pending', 'Notice Period', 'Checked Out'];
    if (!validStatuses.contains(selectedStatus)) {
      selectedStatus = 'Active';
    }

    String? localError;
    bool isSaving = false;

    showPremiumDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final textPri = isDark ? Colors.white : AppTheme.textDark;
            final textSec = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;
            final fieldBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
            final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

            InputDecoration inputDeco({
              required String label,
              required String hint,
              Widget? prefixIcon,
              Widget? suffixIcon,
              String? prefixText,
            }) {
              return InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: textSec, fontSize: 13, fontWeight: FontWeight.w500),
                hintText: hint,
                hintStyle: TextStyle(color: textSec.withValues(alpha: 0.6), fontSize: 13),
                prefixIcon: prefixIcon,
                suffixIcon: suffixIcon,
                prefixText: prefixText,
                prefixStyle: TextStyle(color: textPri, fontWeight: FontWeight.w600),
                filled: true,
                fillColor: fieldBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderCol),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderCol),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                ),
              );
            }

            return PremiumDialog(
              maxWidth: 680,
              title: 'Edit Resident Details',
              subtitle: resident['name'] ?? resident['full_name'] ?? 'Resident',
              icon: Icons.edit_note_rounded,
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: textSec, fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final nameVal = nameController.text.trim();
                          final phoneVal = phoneController.text.trim();
                          final emailVal = emailController.text.trim();
                          final emVal = emergencyController.text.trim();
                          final dobVal = dobController.text.trim();
                          final occVal = occupationController.text.trim();
                          final addrVal = addressController.text.trim();
                          final pinVal = pincodeController.text.trim();
                          final rentVal = int.tryParse(rentController.text.trim()) ?? 8000;
                          final depVal = int.tryParse(depositController.text.trim()) ?? 16000;

                          if (nameVal.isEmpty) {
                            setDialogState(() => localError = 'Full name cannot be empty');
                            return;
                          }
                          if (phoneVal.isEmpty) {
                            setDialogState(() => localError = 'Phone number cannot be empty');
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            localError = null;
                          });

                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(dialogCtx);

                          // 1. Update In-Memory Resident
                          resident['name'] = nameVal;
                          resident['full_name'] = nameVal;
                          resident['phone'] = phoneVal;
                          resident['email'] = emailVal;
                          resident['emergency_contact'] = emVal;
                          resident['emergency_contact_phone'] = emVal;
                          resident['dob'] = dobVal;
                          resident['date_of_birth'] = dobVal;
                          resident['gender'] = selectedGender;
                          resident['occupation'] = occVal;
                          resident['address'] = addrVal;
                          resident['permanent_address'] = addrVal;
                          resident['pincode'] = pinVal;
                          resident['rent'] = rentVal;
                          resident['monthly_rent'] = rentVal;
                          resident['deposit'] = depVal;
                          resident['security_deposit'] = depVal;
                          resident['status'] = selectedStatus;

                          // 2. Sync with AppData.residents
                          final resId = resident['id']?.toString();
                          for (var r in AppData.residents) {
                            if ((resId != null && resId.isNotEmpty && r['id']?.toString() == resId) ||
                                identical(r, resident)) {
                              r['name'] = nameVal;
                              r['full_name'] = nameVal;
                              r['phone'] = phoneVal;
                              r['email'] = emailVal;
                              r['emergency_contact'] = emVal;
                              r['dob'] = dobVal;
                              r['gender'] = selectedGender;
                              r['occupation'] = occVal;
                              r['address'] = addrVal;
                              r['permanent_address'] = addrVal;
                              r['pincode'] = pinVal;
                              r['rent'] = rentVal;
                              r['monthly_rent'] = rentVal;
                              r['deposit'] = depVal;
                              r['security_deposit'] = depVal;
                              r['status'] = selectedStatus;
                              break;
                            }
                          }
                          AppData.saveResidentsToStorage();

                          // 3. Sync to Backend API
                          if (resId != null && resId.isNotEmpty && !resId.startsWith('mock-') && !resId.startsWith('r-')) {
                            try {
                              final apiPayload = <String, dynamic>{
                                'full_name': nameVal,
                                'name': nameVal,
                                'phone': phoneVal,
                                'email': emailVal.isNotEmpty ? emailVal : null,
                                'emergency_contact': emVal,
                                'dob': dobVal,
                                'gender': selectedGender,
                                'occupation': occVal,
                                'address': addrVal,
                                'pincode': pinVal,
                                'monthly_rent': rentVal.toDouble(),
                                'rent': rentVal.toDouble(),
                                'security_deposit': depVal.toDouble(),
                                'deposit': depVal.toDouble(),
                                'status': selectedStatus.toUpperCase().replaceAll(' ', '_'),
                              };
                              await AdminApiService.updateResident(resId, apiPayload);
                            } catch (e) {
                              debugPrint('API updateResident error: $e');
                            }
                          }

                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Resident profile for "$nameVal" updated successfully!'),
                              backgroundColor: AppTheme.statusOk,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          onComplete?.call();
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    isSaving ? 'Saving...' : 'Save Changes',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (localError != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        localError!,
                                        style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Section 1: Personal Info & Phone
                            _buildFormSectionHeader('Personal Information'),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: nameController,
                                    style: TextStyle(color: textPri, fontSize: 14),
                                    decoration: inputDeco(
                                      label: 'Full Name *',
                                      hint: 'e.g. Priya Sharma',
                                      prefixIcon: const Icon(Icons.person_outline, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextField(
                                    controller: phoneController,
                                    keyboardType: TextInputType.phone,
                                    style: TextStyle(color: textPri, fontSize: 14, fontWeight: FontWeight.w600),
                                    decoration: inputDeco(
                                      label: 'Mobile Number *',
                                      hint: 'e.g. 9876543210',
                                      prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: dobController,
                                    style: TextStyle(color: textPri, fontSize: 14),
                                    decoration: inputDeco(
                                      label: 'Date of Birth',
                                      hint: 'DD/MM/YYYY',
                                      prefixIcon: const Icon(Icons.cake_outlined, size: 20, color: AppTheme.primaryBlue),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.calendar_month_outlined, size: 20, color: AppTheme.primaryBlue),
                                        onPressed: () async {
                                          final picked = await showDatePicker(
                                            context: ctx,
                                            initialDate: DateTime(2000, 1, 1),
                                            firstDate: DateTime(1960),
                                            lastDate: DateTime.now(),
                                          );
                                          if (picked != null) {
                                            final d = picked.day.toString().padLeft(2, '0');
                                            final m = picked.month.toString().padLeft(2, '0');
                                            dobController.text = '$d/$m/${picked.year}';
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedGender,
                                    dropdownColor: cardBg,
                                    style: TextStyle(color: textPri, fontSize: 14),
                                    decoration: inputDeco(
                                      label: 'Gender',
                                      hint: 'Select Gender',
                                      prefixIcon: const Icon(Icons.wc_outlined, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setDialogState(() => selectedGender = val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: occupationController,
                              style: TextStyle(color: textPri, fontSize: 14),
                              decoration: inputDeco(
                                label: 'Occupation',
                                hint: 'e.g. Software Engineer, Student',
                                prefixIcon: const Icon(Icons.work_outline, size: 20, color: AppTheme.primaryBlue),
                              ),
                            ),

                            const SizedBox(height: 22),
                            // Section 2: Contact & Address
                            _buildFormSectionHeader('Contact & Address'),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: TextStyle(color: textPri, fontSize: 14),
                                    decoration: inputDeco(
                                      label: 'Email Address',
                                      hint: 'e.g. resident@example.com',
                                      prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextField(
                                    controller: emergencyController,
                                    keyboardType: TextInputType.phone,
                                    style: TextStyle(color: textPri, fontSize: 14),
                                    decoration: inputDeco(
                                      label: 'Emergency Contact',
                                      hint: 'e.g. 9876543299',
                                      prefixIcon: const Icon(Icons.contact_phone_outlined, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: addressController,
                              maxLines: 2,
                              style: TextStyle(color: textPri, fontSize: 14),
                              decoration: inputDeco(
                                label: 'Permanent Address',
                                hint: 'Door No, Street, Landmark, City, State',
                                prefixIcon: const Icon(Icons.location_on_outlined, size: 20, color: AppTheme.primaryBlue),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: pincodeController,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: textPri, fontSize: 14),
                              decoration: inputDeco(
                                label: 'Pincode',
                                hint: 'e.g. 560001',
                                prefixIcon: const Icon(Icons.pin_drop_outlined, size: 20, color: AppTheme.primaryBlue),
                              ),
                            ),

                            const SizedBox(height: 22),
                            // Section 3: Stay & Financials
                            _buildFormSectionHeader('Stay & Financials'),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: rentController,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: textPri, fontSize: 14, fontWeight: FontWeight.w600),
                                    decoration: inputDeco(
                                      label: 'Monthly Rent',
                                      hint: '8000',
                                      prefixText: '₹ ',
                                      prefixIcon: const Icon(Icons.currency_rupee, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextField(
                                    controller: depositController,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: textPri, fontSize: 14, fontWeight: FontWeight.w600),
                                    decoration: inputDeco(
                                      label: 'Security Deposit',
                                      hint: '16000',
                                      prefixText: '₹ ',
                                      prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppTheme.primaryBlue),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              initialValue: selectedStatus,
                              dropdownColor: cardBg,
                              style: TextStyle(color: textPri, fontSize: 14),
                              decoration: inputDeco(
                                label: 'Resident Status',
                                hint: 'Select Status',
                                prefixIcon: const Icon(Icons.verified_user_outlined, size: 20, color: AppTheme.primaryBlue),
                              ),
                              items: validStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => selectedStatus = val);
                                }
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



  // Public static method to show Resident Profile Modal from anywhere
  static void showResidentProfileModal(
    BuildContext context,
    Map<String, dynamic> resident, {
    VoidCallback? onStateChanged,
  }) {
    String initials = '';
    final parts = (resident['name'] ?? '').toString().trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      initials += parts[0][0].toUpperCase();
      if (parts.length > 1 && parts[1].isNotEmpty) {
        initials += parts[1][0].toUpperCase();
      }
    }
    if (initials.isEmpty) initials = 'R';

    showPremiumDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final sectionBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
        final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final textPri = isDark ? Colors.white : AppTheme.textDark;
        final textSec = isDark ? const Color(0xFF94A3B8) : AppTheme.textGrey;

        final isPending = resident['status'] == 'Pending';
        final isActive = resident['status'] == 'Active';
        final statusColor = isPending
            ? const Color(0xFFD97706)
            : (isActive ? const Color(0xFF10B981) : AppTheme.textGrey);
        final statusText = isPending
            ? 'Pending Resident'
            : (isActive ? 'Active Resident' : '${resident['status'] ?? 'Active'} Resident');

        return PremiumDialog(
          maxWidth: 640,
          title: resident['name'] ?? 'Resident Profile',
          subtitle: statusText,
          icon: Icons.badge_outlined,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                final rIndex = AppData.residents.indexOf(resident);
                showTransferModal(context, resident, rIndex >= 0 ? rIndex : 0, onComplete: onStateChanged);
              },
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Change Room'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryTeal,
                side: const BorderSide(color: AppTheme.primaryTeal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                showEditResidentDialog(
                  context,
                  resident,
                  onComplete: () {
                    onStateChanged?.call();
                    showResidentProfileModal(context, resident, onStateChanged: onStateChanged);
                  },
                );
              },
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                final rIndex = AppData.residents.indexOf(resident);
                showCheckoutModal(context, resident, rIndex >= 0 ? rIndex : 0, onComplete: onStateChanged);
              },
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Proceed Exit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.statusRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header banner with Initials and info
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderCol),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: isPending ? const Color(0xFFFEF3C7) : AppTheme.lightTeal,
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isPending ? const Color(0xFFD97706) : AppTheme.primaryTeal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resident['name'] ?? 'Unknown Resident',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPri),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPending ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isPending ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0)),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                resident['phone'] ?? '',
                                style: TextStyle(fontSize: 12, color: textSec),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

                  // Card 1: Personal Information (Full Name, DOB, Gender, Occupation in 2 columns)
                  _buildProfileSectionCard(
                    title: 'Personal Information',
                    icon: Icons.person_outline,
                    sectionBg: sectionBg,
                    borderCol: borderCol,
                    textPri: textPri,
                    children: [
                      Row(
                        children: [
                          _buildProfileInfoBlock('Full Name', resident['name'] ?? 'Not provided', textPri: textPri, textSec: textSec),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock('DOB', resident['dob'] ?? '15/05/1998', textPri: textPri, textSec: textSec),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildProfileInfoBlock('Gender', resident['gender'] ?? 'Female', textPri: textPri, textSec: textSec),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock('Occupation', resident['occupation'] ?? 'Software Engineer', textPri: textPri, textSec: textSec),
                        ],
                      ),
                    ],
                  ),

                  // Card 2: Contact (Mobile Number, Email, Emergency Contact)
                  _buildProfileSectionCard(
                    title: 'Contact',
                    icon: Icons.phone_outlined,
                    sectionBg: sectionBg,
                    borderCol: borderCol,
                    textPri: textPri,
                    children: [
                      Row(
                        children: [
                          _buildProfileInfoBlock('Mobile Number', resident['phone'] ?? 'Not provided', textPri: textPri, textSec: textSec),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock('Email', resident['email'] ?? 'Not provided', textPri: textPri, textSec: textSec),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildProfileInfoBlock('Emergency Contact', resident['emergency_contact'] ?? 'Not provided', textPri: textPri, textSec: textSec),
                          const SizedBox(width: 16),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ),

                  // Card 3: Stay Info (Status, Property Name, Room & Bed, Monthly Rent, Joining Date, Security Deposit)
                  _buildProfileSectionCard(
                    title: 'Stay Info',
                    icon: Icons.hotel_outlined,
                    sectionBg: sectionBg,
                    borderCol: borderCol,
                    textPri: textPri,
                    children: [
                      Row(
                        children: [
                          _buildProfileInfoBlock(
                            'Status',
                            resident['status'] ?? 'Active',
                            textPri: textPri,
                            textSec: textSec,
                            customValue: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isPending
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                resident['status'] ?? 'Active',
                                style: TextStyle(
                                  color: isPending ? const Color(0xFFB45309) : const Color(0xFF16A34A),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock(
                            'Property Name',
                            resident['property_name'] ?? resident['property'] ?? 'BNR Luxury PG',
                            textPri: textPri,
                            textSec: textSec,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildProfileInfoBlock(
                            'Room & Bed',
                            resident['room'] != null && resident['room'].toString().isNotEmpty
                                ? 'Room ${resident['room']} • ${resident['bed'] ?? 'Bed A'}'
                                : 'Pending Allocation',
                            textPri: textPri,
                            textSec: textSec,
                          ),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock(
                            'Monthly Rent',
                            '₹${resident['rent'] ?? 8000}/mo',
                            textPri: textPri,
                            textSec: textSec,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildProfileInfoBlock(
                            'Joining Date',
                            resident['joining_date'] ?? '01 Jan 2026',
                            textPri: textPri,
                            textSec: textSec,
                          ),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock(
                            'Security Deposit',
                            '₹${resident['deposit'] ?? 16000}',
                            textPri: textPri,
                            textSec: textSec,
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Card 4: Address (Permanent Address, Pincode)
                  _buildProfileSectionCard(
                    title: 'Address',
                    icon: Icons.location_on_outlined,
                    sectionBg: sectionBg,
                    borderCol: borderCol,
                    textPri: textPri,
                    children: [
                      Row(
                        children: [
                          _buildProfileInfoBlock('Permanent Address', resident['address'] ?? 'Not provided', textPri: textPri, textSec: textSec),
                          const SizedBox(width: 16),
                          _buildProfileInfoBlock('Pincode', resident['pincode'] ?? 'Not provided', textPri: textPri, textSec: textSec),
                        ],
                      ),
                    ],
                  ),

                  // Card 5: Documents (View Aadhaar, View PAN)
                  _buildProfileSectionCard(
                    title: 'Documents',
                    icon: Icons.description_outlined,
                    sectionBg: sectionBg,
                    borderCol: borderCol,
                    textPri: textPri,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDocumentPreviewDialog(context, 'Aadhaar Card', resident['name'] ?? '', resident['id']?.toString(), 'aadhaar_front'),
                              icon: const Icon(Icons.remove_red_eye_outlined, size: 18, color: AppTheme.primaryBlue),
                              label: const Text(
                                'View Aadhaar',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFBFDBFE)),
                                backgroundColor: const Color(0xFFEFF6FF),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDocumentPreviewDialog(context, 'PAN Card', resident['name'] ?? '', resident['id']?.toString(), 'pan_card'),
                              icon: const Icon(Icons.remove_red_eye_outlined, size: 18, color: AppTheme.primaryBlue),
                              label: const Text(
                                'View PAN',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFBFDBFE)),
                                backgroundColor: const Color(0xFFEFF6FF),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            ],
          ),
        );
      },
    );
  }

  // Public static method to show Room Transfer modal
  static void showTransferModal(
    BuildContext context,
    Map<String, dynamic> resident,
    int residentIndex, {
    VoidCallback? onComplete,
  }) {
    final newRoomController = TextEditingController();
    String? localError;
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return PremiumDialog(
              maxWidth: 440,
              title: 'Transfer Room',
              subtitle: resident['name'] ?? 'Resident',
              icon: Icons.swap_horiz_rounded,
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogContext);
                          final newRoomNum = newRoomController.text.trim();
                          if (newRoomNum.isEmpty) {
                            setModalState(() => localError = 'Please enter a room number');
                            return;
                          }

                          setModalState(() => isSubmitting = true);

                          final errorMessage = AppData.transferResident(resident['name'], newRoomNum);

                          if (errorMessage != null) {
                            setModalState(() {
                              isSubmitting = false;
                              localError = errorMessage;
                            });
                            return;
                          }

                          resident['room'] = newRoomNum;
                          final resId = resident['id']?.toString();
                          if (resId != null && resId.isNotEmpty && !resId.startsWith('res-')) {
                            final targetRoom = AppData.rooms.cast<Map<String, dynamic>?>().firstWhere(
                              (r) => r?['number']?.toString() == newRoomNum,
                              orElse: () => null,
                            );
                            final targetRoomId = targetRoom?['id']?.toString();
                            if (targetRoomId != null && targetRoomId.isNotEmpty) {
                              try {
                                await AdminApiService.transferResident(
                                  residentId: resId,
                                  newRoomId: targetRoomId,
                                );
                              } catch (e) {
                                debugPrint('API transferResident error: $e');
                              }
                            }
                          }

                          nav.pop();
                          onComplete?.call();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Successfully transferred to Room $newRoomNum!'),
                              backgroundColor: AppTheme.statusOk,
                            ),
                          );
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(isSubmitting ? 'Transferring...' : 'Confirm Transfer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Current Allocation', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                        Text(
                          'Room ${resident['room'] ?? 'Unassigned'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PremiumFormField(
                    controller: newRoomController,
                    label: 'New Room Number',
                    hintText: 'e.g. 102, 201',
                    prefixIcon: Icons.meeting_room_rounded,
                    isRequired: true,
                    errorMessage: localError,
                    onChanged: (_) {
                      if (localError != null) {
                        setModalState(() => localError = null);
                      }
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

  // Public static method to show Checkout modal
  static void showCheckoutModal(
    BuildContext context,
    Map<String, dynamic> resident,
    int residentIndex, {
    VoidCallback? onComplete,
  }) {
    final deductionController = TextEditingController(text: '0');
    final deposit = (resident['deposit'] as num?)?.toInt() ?? 0;
    bool isSubmitting = false;

    final messenger = ScaffoldMessenger.of(context);
    showPremiumDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (builderCtx, setModalState) {
            final deduction = int.tryParse(deductionController.text) ?? 0;
            final refundAmount = deposit - deduction;

            return PremiumDialog(
              maxWidth: 480,
              title: 'Resident Checkout',
              subtitle: resident['name'] ?? 'Resident',
              icon: Icons.logout_rounded,
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final nav = Navigator.of(dialogCtx);
                          final resId = resident['id']?.toString();
                          setModalState(() => isSubmitting = true);
                          if (resId != null && resId.isNotEmpty && !resId.startsWith('res-')) {
                            try {
                              await AdminApiService.checkoutResident(
                                resId,
                                damageCharges: deduction.toDouble(),
                              );
                            } catch (e) {
                              debugPrint('API checkoutResident error: $e');
                            }
                          }

                          if (resident['room'] != null) {
                            final roomIndex = AppData.rooms.indexWhere((r) => r['number'].toString() == resident['room'].toString());
                            if (roomIndex != -1) {
                              final beds = AppData.rooms[roomIndex]['beds'] as List;
                              final bedIndex = beds.indexWhere((b) => b['occupant'] == resident['name']);
                              if (bedIndex != -1) {
                                beds[bedIndex]['status'] = 'Available';
                                beds[bedIndex]['occupant'] = null;
                              }
                            }
                          }

                          AppData.residents.remove(resident);
                          AppData.saveResidentsToStorage();

                          nav.pop();
                          onComplete?.call();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Checked out ${resident['name']}. Refund of ₹ $refundAmount processed.'),
                              backgroundColor: AppTheme.statusOk,
                            ),
                          );
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(isSubmitting ? 'Processing...' : 'Confirm Checkout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.statusRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Room & Property', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                            Text(
                              resident['room'] != null && resident['room'].toString().isNotEmpty
                                  ? 'Room ${resident['room']}'
                                  : 'Not Assigned',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                            ),
                          ],
                        ),
                        const Divider(height: 16, color: Color(0xFFE2E8F0)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Security Deposit', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                            Text('₹ $deposit', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PremiumFormField(
                    controller: deductionController,
                    label: 'Deductions (Pending rent, damages)',
                    prefixIcon: Icons.currency_rupee_rounded,
                    keyboardType: TextInputType.number,
                    onChanged: (val) => setModalState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Net Refund to Resident', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF065F46))),
                        Text(
                          '₹ ${refundAmount < 0 ? 0 : refundAmount}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.statusOk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildFormSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
    );
  }

  static Widget _buildProfileSectionCard({
    required String title,
    required IconData icon,
    required Color sectionBg,
    required Color borderCol,
    required Color textPri,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sectionBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: textPri),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPri),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  static Widget _buildProfileInfoBlock(
    String label,
    String value, {
    required Color textPri,
    required Color textSec,
    Color? valueColor,
    Widget? customValue,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSec,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if (customValue != null)
            customValue
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? textPri,
              ),
            ),
        ],
      ),
    );
  }

  static void _showDocumentPreviewDialog(
    BuildContext context,
    String docType,
    String residentName, [
    String? residentId,
    String? docKey,
  ]) {
    showPremiumDialog(
      context: context,
      builder: (ctx) => PremiumDialog(
        maxWidth: 520,
        title: '$docType - $residentName',
        subtitle: 'Identity document verification preview',
        icon: Icons.document_scanner_rounded,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 240,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Center(
                child: residentId != null && residentId.isNotEmpty
                    ? FutureBuilder<Uint8List?>(
                        future: AdminApiService.getKycDocumentBytes(residentId, docKey ?? 'aadhaar_front'),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal));
                          }
                          if (snapshot.hasData && snapshot.data != null) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                snapshot.data!,
                                height: 240,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            );
                          }
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.document_scanner_outlined, size: 48, color: AppTheme.textGrey),
                              const SizedBox(height: 10),
                              Text('Verified $docType Image', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                              const SizedBox(height: 4),
                              const Text('Uploaded by resident', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                            ],
                          );
                        },
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.document_scanner_outlined, size: 48, color: AppTheme.textGrey),
                          SizedBox(height: 10),
                          Text('Verified Document Image', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                          SizedBox(height: 4),
                          Text('Uploaded by resident', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResidentsScreenState extends State<ResidentsScreen> {
  List<Map<String, dynamic>> get _residents => AppData.residents;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedResidentStatus = 'All Resident Statuses';
  String _selectedKycStatus = 'Verified';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    AppData.saveResidentsToStorage();
    AppData.selectedPropertyIdNotifier.addListener(_loadResidentsFromApi);
    _loadResidentsFromApi();
  }

  @override
  void dispose() {
    AppData.selectedPropertyIdNotifier.removeListener(_loadResidentsFromApi);
    _searchController.dispose();
    super.dispose();
  }

  void _loadResidentsFromApi() async {
    final propId = AppData.selectedPropertyId;
    if (propId == null || propId.isEmpty || propId.startsWith('p')) return;
    try {
      final list = await AdminApiService.getResidents(propertyId: propId);
      if (list.isNotEmpty && mounted) {
        setState(() {
          AppData.residents = list.map((r) => <String, dynamic>{
            'id': r['id']?.toString() ?? '',
            'name': r['full_name'] ?? r['name'] ?? 'Resident',
            'phone': r['phone'] ?? '',
            'email': r['email'] ?? '',
            'room': r['room_number'] ?? r['room'] ?? '',
            'room_number': r['room_number'] ?? r['room'] ?? '',
            'floor': r['floor'] ?? '1st Floor',
            'bed': r['bed_number'] ?? r['bed'] ?? 'Bed A',
            'rent': (r['monthly_rent'] ?? 8000).toInt(),
            'deposit': (r['security_deposit'] ?? 16000).toInt(),
            'kyc': r['kyc_status'] == 'VERIFIED' ? 'Verified' : (r['kyc_status'] == 'REJECTED' ? 'Rejected' : 'Pending'),
            'status': r['status'] == 'ACTIVE' ? 'Active' : (r['status'] == 'PENDING' ? 'Pending' : (r['status'] ?? 'Active')),
            'dob': r['date_of_birth']?.toString() ?? '15/05/2000',
            'gender': r['gender'] ?? 'Male',
            'occupation': r['occupation'] ?? 'Software Engineer',
            'emergency_contact': r['emergency_contact_phone'] ?? r['emergency_contact_name'] ?? 'Not provided',
            'address': r['permanent_address'] ?? 'Not provided',
            'pincode': r['pincode'] ?? '560001',
            'aadhaar_number': r['id_proof_number_masked'] ?? 'Not provided',
            'pan_number': r['pan_number'] ?? 'Not provided',
            'property_name': r['property_name'] ?? AppData.selectedProperty,
            'joining_date': r['check_in_date']?.toString() ?? 'Today',
            'role': 'Resident',
          }).toList();
          AppData.saveResidentsToStorage();
        });
      }
    } catch (e) {
      debugPrint('API getResidents error: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredResidents {
    return _residents.where((res) {
      final query = _searchQuery.toLowerCase().trim();
      if (query.isNotEmpty) {
        final name = (res['name'] ?? '').toString().toLowerCase();
        final phone = (res['phone'] ?? '').toString().toLowerCase();
        final room = (res['room'] ?? res['room_number'] ?? '').toString().toLowerCase();
        if (!name.contains(query) && !phone.contains(query) && !room.contains(query)) {
          return false;
        }
      }

      if (_selectedResidentStatus != 'All Resident Statuses') {
        final status = (res['status'] ?? '').toString().trim();
        if (status.toLowerCase() != _selectedResidentStatus.toLowerCase()) {
          return false;
        }
      }

      if (_selectedKycStatus.isNotEmpty) {
        final kyc = (res['kyc'] ?? '').toString().trim();
        if (kyc.toLowerCase() != _selectedKycStatus.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showAddResidentDialog() {
    ResidentsScreen.showAddResidentDialog(context, onComplete: () {
      setState(() {});
      _loadResidentsFromApi();
    });
  }

  void _showKycModal(BuildContext context, Map<String, dynamic> resident, int residentIndex) {
    bool isVerified = resident['kyc'] == 'Verified';
    bool isRejected = resident['kyc'] == 'Rejected';
    final resId = resident['id']?.toString() ?? '';
    final messenger = ScaffoldMessenger.of(context);

    showPremiumDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return PremiumDialog(
              maxWidth: 560,
              icon: isVerified
                  ? Icons.verified_rounded
                  : (isRejected ? Icons.gpp_bad_rounded : Icons.verified_user_rounded),
              iconColor: isVerified
                  ? AppTheme.statusOk
                  : (isRejected ? AppTheme.statusRed : AppTheme.primaryTeal),
              iconBgColor: isVerified
                  ? const Color(0xFFE8F5E9)
                  : (isRejected ? const Color(0xFFFFEBEE) : AppTheme.lightTeal),
              title: 'KYC: ${resident['name'] ?? 'Resident'}',
              subtitle: isVerified
                  ? 'Documents fully verified and approved'
                  : (isRejected
                      ? 'Identity documents rejected by administration'
                      : 'Review resident identity documents and take action'),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isVerified) ...[
                    const PremiumDialogBanner(
                      status: BannerStatus.success,
                      title: 'KYC Fully Verified',
                      message: 'This resident has completed verification and identity documents are approved.',
                    ),
                  ] else if (isRejected) ...[
                    const PremiumDialogBanner(
                      status: BannerStatus.error,
                      title: 'KYC Verification Rejected',
                      message: 'The identity documents were rejected. Please ask the resident to re-upload clear copies.',
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.lightTeal.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primaryTeal),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Please inspect both Aadhaar and PAN documents before approving or rejecting.',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryTeal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.badge_outlined, size: 16, color: AppTheme.textGrey),
                        const SizedBox(width: 6),
                        Text(
                          'Aadhaar Card',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<Uint8List?>(
                      future: resId.isNotEmpty ? AdminApiService.getKycDocumentBytes(resId, 'aadhaar_front') : Future.value(null),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal),
                              ),
                            ),
                          );
                        }
                        if (snapshot.hasData && snapshot.data != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.borderColor),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Image.memory(snapshot.data!, height: 180, width: double.infinity, fit: BoxFit.cover),
                            ),
                          );
                        }
                        return Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.description_outlined, size: 32, color: AppTheme.textGrey.withValues(alpha: 0.6)),
                                const SizedBox(height: 6),
                                Text(
                                  'Aadhaar document preview not available',
                                  style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textGrey),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.credit_card_outlined, size: 16, color: AppTheme.textGrey),
                        const SizedBox(width: 6),
                        Text(
                          'PAN Card',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<Uint8List?>(
                      future: resId.isNotEmpty ? AdminApiService.getKycDocumentBytes(resId, 'pan_card') : Future.value(null),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal),
                              ),
                            ),
                          );
                        }
                        if (snapshot.hasData && snapshot.data != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.borderColor),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Image.memory(snapshot.data!, height: 180, width: double.infinity, fit: BoxFit.cover),
                            ),
                          );
                        }
                        return Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.description_outlined, size: 32, color: AppTheme.textGrey.withValues(alpha: 0.6)),
                                const SizedBox(height: 6),
                                Text(
                                  'PAN document preview not available',
                                  style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textGrey),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                if (!isVerified) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      final reasonController = TextEditingController();
                      String? err;
                      bool isRejecting = false;

                      showPremiumDialog(
                        context: context,
                        builder: (rCtx) => StatefulBuilder(
                          builder: (dialogContext, setRState) => PremiumDialog(
                            maxWidth: 440,
                            icon: Icons.gpp_bad_rounded,
                            iconColor: AppTheme.statusRed,
                            iconBgColor: const Color(0xFFFFEBEE),
                            title: 'Reject KYC Verification',
                            subtitle: resident['name'] ?? 'Resident',
                            body: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const PremiumDialogBanner(
                                  status: BannerStatus.warning,
                                  title: 'Rejection Notice',
                                  message: 'Please provide a clear reason so the resident understands what to fix when re-uploading.',
                                ),
                                const SizedBox(height: 16),
                                PremiumFormField(
                                  label: 'Reason for Rejection',
                                  hintText: 'e.g. Identity document is unclear, blurred, or expired',
                                  controller: reasonController,
                                  required: true,
                                  maxLines: 3,
                                  prefixIcon: Icons.notes_rounded,
                                ),
                                if (err != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    err!,
                                    style: GoogleFonts.manrope(
                                      color: AppTheme.statusRed,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            actions: [
                              OutlinedButton(
                                onPressed: isRejecting ? null : () => Navigator.pop(rCtx),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.borderColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: isRejecting
                                    ? null
                                    : () async {
                                        final notes = reasonController.text.trim();
                                        if (notes.isEmpty) {
                                          setRState(() => err = 'Please enter a valid rejection reason.');
                                          return;
                                        }
                                        setRState(() => isRejecting = true);
                                        final resId = _residents[residentIndex]['id']?.toString() ?? '';
                                        if (resId.isNotEmpty) {
                                          try {
                                            await AdminApiService.rejectResidentKYC(resId, notes: notes);
                                          } catch (_) {}
                                        }
                                        setState(() {
                                          _residents[residentIndex]['kyc'] = 'Rejected';
                                        });
                                        _loadResidentsFromApi();
                                        if (rCtx.mounted) Navigator.pop(rCtx);
                                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('KYC Rejected. Resident notified to re-upload.'),
                                            backgroundColor: AppTheme.statusRed,
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.statusRed,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                ),
                                child: isRejecting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(
                                        'Reject KYC',
                                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.statusRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(
                      'Reject',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final resId = _residents[residentIndex]['id']?.toString() ?? '';
                      if (resId.isNotEmpty) {
                        try {
                          await AdminApiService.verifyResidentKYC(resId);
                        } catch (_) {}
                      }
                      setState(() {
                        _residents[residentIndex]['kyc'] = 'Verified';
                      });
                      _loadResidentsFromApi();
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('KYC Verified Successfully!'),
                          backgroundColor: AppTheme.statusOk,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.statusOk,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      'Verify Documents',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildKycStatusDot(String kycStatus) {
    Color dotColor;
    String label = kycStatus;
    if (kycStatus.toLowerCase() == 'verified') {
      dotColor = const Color(0xFF10B981);
      label = 'Verified';
    } else if (kycStatus.toLowerCase() == 'rejected') {
      dotColor = const Color(0xFFEF4444);
      label = 'Rejected';
    } else {
      dotColor = const Color(0xFFF59E0B);
      label = 'Pending';
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
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dotColor),
        ),
      ],
    );
  }

  Widget _buildResidentStatusBadge(String status) {
    Color bg;
    Color text;
    if (status == 'Active') {
      bg = const Color(0xFFECFDF5);
      text = const Color(0xFF059669);
    } else if (status == 'Notice Period') {
      bg = const Color(0xFFFFFBEB);
      text = const Color(0xFFD97706);
    } else {
      bg = const Color(0xFFF1F5F9);
      text = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalResidents = _residents.length;
    final activeResidents = _residents.where((r) => r['status'] == 'Active').length;
    final pendingKyc = _residents.where((r) => r['kyc'] == 'Pending' || r['kyc'] == 'Under Review').length;
    final verifiedKyc = _residents.where((r) => r['kyc'] == 'Verified').length;
    final filtered = _filteredResidents;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          const Text(
            'Residents & KYC',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),

          // 1. KPI Summary Cards
          TableKpiGrid(
            cards: [
              TableKpiCard(
                title: 'Total Residents',
                value: '$totalResidents',
                icon: Icons.people_alt_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
              ),
              TableKpiCard(
                title: 'Active Residents',
                value: '$activeResidents',
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              ),
              TableKpiCard(
                title: 'Pending KYC',
                value: '$pendingKyc',
                icon: Icons.pending_actions_outlined,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFFFBEB),
              ),
              TableKpiCard(
                title: 'Verified Profiles',
                value: '$verifiedKyc',
                icon: Icons.verified_user_outlined,
                iconColor: const Color(0xFF7C3AED),
                iconBgColor: const Color(0xFFF5F3FF),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Filter Bar
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
                    hintText: 'Search by name, phone, room...',
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

                final residentStatusDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedResidentStatus,
                  items: const ['All Resident Statuses', 'Active', 'Notice Period', 'Checked Out'],
                  onChanged: (v) => setState(() => _selectedResidentStatus = v),
                );

                final kycStatusDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedKycStatus,
                  items: const ['Verified', 'Pending', 'Rejected'],
                  onChanged: (v) => setState(() => _selectedKycStatus = v),
                );

                final monthYearFilter = MonthYearSelector(
                  selectedMonth: _selectedMonth,
                  selectedYear: _selectedYear,
                  onChanged: (m, y) => setState(() {
                    _selectedMonth = m;
                    _selectedYear = y;
                  }),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: searchField,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          monthYearFilter,
                          SizedBox(width: 175, child: residentStatusDropdown),
                          SizedBox(width: 140, child: kycStatusDropdown),
                        ],
                      ),
                    ],
                  );
                }

                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: searchField,
                    ),
                    monthYearFilter,
                    SizedBox(width: 175, child: residentStatusDropdown),
                    SizedBox(width: 130, child: kycStatusDropdown),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // 3. Data Table
          Container(
            decoration: modernTableDecoration,
              child: filtered.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outline,
                      title: 'No matching residents',
                      subtitle: _searchQuery.isNotEmpty || _selectedResidentStatus != 'All Resident Statuses' || _selectedKycStatus != 'All KYC Statuses'
                          ? 'Try adjusting your search filters'
                          : 'Onboard your first resident to get started',
                      actionLabel: 'Onboard Resident',
                      onAction: _showAddResidentDialog,
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
                                  modernTableColumn('RESIDENT NAME'),
                                  modernTableColumn('PROPERTY'),
                                  modernTableColumn('ROOM'),
                                  modernTableColumn('JOINING DATE'),
                                  modernTableColumn('MONTHLY RENT'),
                                  modernTableColumn('KYC STATUS'),
                                  modernTableColumn('STATUS'),
                                  modernTableColumn('ACTIONS'),
                                ],
                                rows: filtered.map((res) {
                                  return DataRow(cells: [
                                    DataCell(
                                      InkWell(
                                        onTap: () => ResidentsScreen.showResidentProfileModal(context, res, onStateChanged: () => setState(() {})),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TableAvatar(name: res['name'] ?? 'R', radius: 18),
                                              const SizedBox(width: 12),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    res['name'] ?? '', 
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 14),
                                                  ),
                                                  if (res['phone'] != null)
                                                    Text(res['phone'], style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        res['property_name'] ?? res['property'] ?? 'Green View PG - Hebbal',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        res['room'] != null && res['room'].toString().isNotEmpty
                                            ? 'Room ${res['room']}'
                                            : 'Not Assigned',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: res['room'] != null && res['room'].toString().isNotEmpty
                                              ? AppTheme.textDark
                                              : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        res['joining_date'] ?? '15 Jan 2026',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '₹ ${res['rent'] ?? 0}', 
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 13),
                                      ),
                                    ),
                                    DataCell(
                                      _buildKycStatusDot(res['kyc'] ?? 'Pending'),
                                    ),
                                    DataCell(
                                      _buildResidentStatusBadge(res['status'] ?? 'Active'),
                                    ),
                                    DataCell(
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: AppTheme.textGrey, size: 20),
                                        tooltip: 'Actions',
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        onSelected: (action) {
                                          final rIndex = _residents.indexOf(res);
                                          if (action == 'profile') {
                                            ResidentsScreen.showResidentProfileModal(context, res, onStateChanged: () {
                                              setState(() {});
                                              _loadResidentsFromApi();
                                            });
                                          } else if (action == 'edit') {
                                            ResidentsScreen.showEditResidentDialog(context, res, onComplete: () {
                                              setState(() {});
                                              _loadResidentsFromApi();
                                            });
                                          } else if (action == 'kyc') {
                                            _showKycModal(context, res, rIndex);
                                          } else if (action == 'transfer') {
                                            ResidentsScreen.showTransferModal(context, res, rIndex, onComplete: () {
                                              setState(() {});
                                              _loadResidentsFromApi();
                                            });
                                          } else if (action == 'checkout') {
                                            ResidentsScreen.showCheckoutModal(context, res, rIndex, onComplete: () {
                                              setState(() {});
                                              _loadResidentsFromApi();
                                            });
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'profile',
                                            child: Row(
                                              children: [
                                                Icon(Icons.account_circle_outlined, size: 18, color: AppTheme.primaryBlue),
                                                SizedBox(width: 8),
                                                Text('View Profile', style: TextStyle(fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryBlue),
                                                SizedBox(width: 8),
                                                Text('Edit Details', style: TextStyle(fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'kyc',
                                            child: Row(
                                              children: [
                                                Icon(Icons.badge_outlined, size: 18, color: Color(0xFF059669)),
                                                SizedBox(width: 8),
                                                Text('Verify KYC', style: TextStyle(fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'transfer',
                                            child: Row(
                                              children: [
                                                Icon(Icons.swap_horiz, size: 18, color: Color(0xFFD97706)),
                                                SizedBox(width: 8),
                                                Text('Transfer Room', style: TextStyle(fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: 'checkout',
                                            child: Row(
                                              children: [
                                                Icon(Icons.logout, size: 18, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Checkout', style: TextStyle(fontSize: 13, color: Colors.red)),
                                              ],
                                            ),
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