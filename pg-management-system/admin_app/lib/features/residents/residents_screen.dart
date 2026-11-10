import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/table_components.dart';
import '../../core/widgets/app_dropdown.dart';

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

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Row(
                children: [
                  const Icon(Icons.person_add_alt_1, color: AppTheme.primaryBlue),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Onboard New Resident',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
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
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final phone = phoneController.text.trim();
                    final roomNo = roomController.text.trim();

                    if (name.isEmpty || phone.isEmpty || roomNo.isEmpty) {
                      setModalState(() {
                        localError = 'Full Name, Phone Number, and Room Number are required!';
                      });
                      return;
                    }

                    String assignedBedName = 'Bed A';
                    final floor = floorController.text.trim().isNotEmpty
                        ? floorController.text.trim()
                        : '1st Floor';

                    final propId = AppData.selectedPropertyId;
                    String? backendResidentId;

                    if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                      // Lookup matching room and bed from AppData.rooms
                      Map<String, dynamic>? matchedRoom;
                      for (var r in AppData.rooms) {
                        if (r['number']?.toString().trim() == roomNo.trim()) {
                          matchedRoom = r;
                          break;
                        }
                      }
                      String? roomId = matchedRoom?['id']?.toString();
                      String? bedId;
                      if (matchedRoom != null && matchedRoom['beds'] is List) {
                        for (var b in matchedRoom['beds'] as List) {
                          if (b['status'] != 'Occupied') {
                            bedId = b['id']?.toString();
                            break;
                          }
                        }
                      }

                      final onboardData = <String, dynamic>{
                        'property_id': propId,
                        'full_name': name,
                        'phone': phone,
                        'email': emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                        'monthly_rent': (int.tryParse(rentController.text) ?? 8000).toDouble(),
                        'security_deposit': (int.tryParse(depositController.text) ?? 16000).toDouble(),
                        'check_in_date': DateTime.now().toIso8601String().substring(0, 10),
                        if (roomId != null && !roomId.startsWith('r-')) 'room_id': roomId,
                        if (bedId != null && !bedId.startsWith('b-')) 'bed_id': bedId,
                      };
                      if (aadhaarController.text.trim().isNotEmpty) {
                        onboardData['id_proof_number'] = aadhaarController.text.trim();
                      }
                      if (panController.text.trim().isNotEmpty) {
                        onboardData['pan_number'] = panController.text.trim();
                      }
                      if (emergencyContactController.text.trim().isNotEmpty) {
                        onboardData['emergency_contact_phone'] = emergencyContactController.text.trim();
                      }

                      try {
                        final onboardRes = await AdminApiService.onboardResident(onboardData);
                        if (onboardRes.isNotEmpty && onboardRes['id'] != null) {
                          backendResidentId = onboardRes['id'].toString();
                        }
                      } catch (e) {
                        setModalState(() {
                          localError = 'Backend onboarding error: $e';
                        });
                        return;
                      }
                    }

                    final errorMessage = AppData.assignResidentToRoom(
                      roomNo,
                      name,
                      floor: floor,
                      onBedAssigned: (bName) {
                        assignedBedName = bName;
                        return bName;
                      },
                      dob: dobController.text.trim().isNotEmpty ? dobController.text.trim() : '15/05/2000',
                      gender: gender,
                      occupation: occupationController.text.trim().isNotEmpty ? occupationController.text.trim() : 'Software Engineer',
                      email: emailController.text.trim().isNotEmpty ? emailController.text.trim() : 'resident@example.com',
                      emergencyContact: emergencyContactController.text.trim().isNotEmpty ? emergencyContactController.text.trim() : 'Not provided',
                      address: addressController.text.trim().isNotEmpty ? addressController.text.trim() : 'Not provided',
                      pincode: pincodeController.text.trim().isNotEmpty ? pincodeController.text.trim() : '560001',
                      aadhaarNumber: aadhaarController.text.trim().isNotEmpty ? aadhaarController.text.trim() : 'Not provided',
                      panNumber: panController.text.trim().isNotEmpty ? panController.text.trim() : 'Not provided',
                      rent: int.tryParse(rentController.text) ?? 8000,
                      deposit: int.tryParse(depositController.text) ?? 16000,
                    );

                    if (errorMessage != null) {
                      setModalState(() {
                        localError = errorMessage;
                      });
                      return;
                    }

                    final newResident = <String, dynamic>{
                      'name': name,
                      'phone': phone,
                      'room': roomNo,
                      'room_number': roomNo,
                      'floor': floor,
                      'bed': assignedBedName,
                      'rent': int.tryParse(rentController.text) ?? 8000,
                      'deposit': int.tryParse(depositController.text) ?? 16000,
                      'kyc': 'Verified',
                      'status': 'Active',
                      'dob': dobController.text.trim().isNotEmpty ? dobController.text.trim() : '15/05/2000',
                      'gender': gender,
                      'occupation': occupationController.text.trim().isNotEmpty ? occupationController.text.trim() : 'Software Engineer',
                      'email': emailController.text.trim().isNotEmpty ? emailController.text.trim() : 'resident@example.com',
                      'emergency_contact': emergencyContactController.text.trim().isNotEmpty ? emergencyContactController.text.trim() : 'Not provided',
                      'address': addressController.text.trim().isNotEmpty ? addressController.text.trim() : 'Not provided',
                      'pincode': pincodeController.text.trim().isNotEmpty ? pincodeController.text.trim() : '560001',
                      'aadhaar_number': aadhaarController.text.trim().isNotEmpty ? aadhaarController.text.trim() : 'Not provided',
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
                          backgroundColor: AppTheme.successGreen,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Onboard Resident'),
                ),
              ],
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

    showDialog(
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
                  borderSide: BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                ),
              );
            }

            return Dialog(
              backgroundColor: cardBg,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderCol)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryBlue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Resident Details',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPri),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Edit name, phone number, stay financials, and address info',
                                  style: TextStyle(fontSize: 12, color: textSec),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                            icon: Icon(Icons.close, color: textSec, size: 20),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
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
                      ),
                    ),

                    // Actions
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: borderCol)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textSec,
                              side: BorderSide(color: borderCol),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final nameVal = nameController.text.trim();
                                    final phoneVal = phoneController.text.trim();

                                    if (nameVal.isEmpty) {
                                      setDialogState(() => localError = 'Full Name cannot be empty.');
                                      return;
                                    }
                                    if (phoneVal.isEmpty) {
                                      setDialogState(() => localError = 'Mobile Number cannot be empty.');
                                      return;
                                    }
                                    final cleanDigits = phoneVal.replaceAll(RegExp(r'\D'), '');
                                    if (cleanDigits.length < 10) {
                                      setDialogState(() => localError = 'Mobile Number must be at least 10 digits.');
                                      return;
                                    }

                                    final messenger = ScaffoldMessenger.of(context);
                                    final navigator = Navigator.of(dialogCtx);

                                    setDialogState(() {
                                      isSaving = true;
                                      localError = null;
                                    });

                                    final rentVal = int.tryParse(rentController.text.trim()) ?? (resident['rent'] ?? 8000);
                                    final depVal = int.tryParse(depositController.text.trim()) ?? (resident['deposit'] ?? 16000);
                                    final emailVal = emailController.text.trim();
                                    final emVal = emergencyController.text.trim();
                                    final dobVal = dobController.text.trim();
                                    final occVal = occupationController.text.trim();
                                    final addrVal = addressController.text.trim();
                                    final pinVal = pincodeController.text.trim();

                                    // 1. Update in-memory resident object
                                    resident['name'] = nameVal;
                                    resident['full_name'] = nameVal;
                                    resident['phone'] = phoneVal;
                                    resident['email'] = emailVal;
                                    resident['emergency_contact'] = emVal;
                                    resident['dob'] = dobVal;
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
                                        backgroundColor: const Color(0xFF10B981),
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
                                : const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(
                              isSaving ? 'Saving...' : 'Save Changes',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
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

        return Dialog(
          backgroundColor: cardBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: CircleAvatar with Initials (amber background), Name, Status Subtitle
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: const Color(0xFFFEF3C7),
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              resident['name'] ?? 'Unknown Resident',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: textPri,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

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

                  const SizedBox(height: 20),

                  // Bottom Action Bar: [Edit] [Change Room] [Proceed Exit]
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
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
                          icon: Icon(Icons.edit_outlined, size: 16, color: textPri),
                          label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, color: textPri)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                            foregroundColor: textPri,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(0, 42),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            final rIndex = AppData.residents.indexOf(resident);
                            showTransferModal(context, resident, rIndex >= 0 ? rIndex : 0, onComplete: onStateChanged);
                          },
                          icon: const Icon(Icons.swap_horiz, size: 18, color: AppTheme.primaryBlue),
                          label: const Text(
                            'Change Room',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : const Color(0xFFEFF6FF),
                            foregroundColor: AppTheme.primaryBlue,
                            side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(0, 42),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            final rIndex = AppData.residents.indexOf(resident);
                            showCheckoutModal(context, resident, rIndex >= 0 ? rIndex : 0, onComplete: onStateChanged);
                          },
                          icon: const Icon(Icons.logout, size: 16, color: Colors.white),
                          label: const Text('Proceed Exit', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(0, 42),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: IconButton(
                icon: Icon(Icons.close, color: textSec, size: 20),
                onPressed: () => Navigator.pop(dialogCtx),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
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

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text('Transfer Resident: ${resident['name']}', overflow: TextOverflow.ellipsis),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Room: ${resident['room']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text('Enter New Room Number:', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newRoomController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 102, 201',
                      ),
                      onChanged: (_) {
                        if (localError != null) {
                          setModalState(() => localError = null);
                        }
                      },
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    ],
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
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(dialogContext);
                    final newRoomNum = newRoomController.text.trim();
                    if (newRoomNum.isEmpty) {
                      setModalState(() => localError = 'Please enter a room number');
                      return;
                    }

                    final errorMessage = AppData.transferResident(resident['name'], newRoomNum);

                    if (errorMessage != null) {
                      setModalState(() => localError = errorMessage);
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
                        backgroundColor: AppTheme.successGreen,
                      ),
                    );
                  },
                  child: const Text('Confirm Transfer'),
                ),
              ],
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
    final deposit = resident['deposit'] ?? 0;

    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (builderCtx, setModalState) {
            final deduction = int.tryParse(deductionController.text) ?? 0;
            final refundAmount = deposit - deduction;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text('Checkout: ${resident['name']}', overflow: TextOverflow.ellipsis),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resident['room'] != null && resident['room'].toString().isNotEmpty
                          ? 'Room: ${resident['room']}'
                          : 'Room: Not Assigned',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Security Deposit:'),
                        Text('₹ $deposit', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Deductions (Pending rent, damages):', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: deductionController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Enter amount'),
                      onChanged: (val) => setModalState(() {}),
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Refund to Resident:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          '₹ ${refundAmount < 0 ? 0 : refundAmount}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final nav = Navigator.of(dialogCtx);
                    final resId = resident['id']?.toString();
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
                        content: Text('Checked out. Refund ₹ $refundAmount processed.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Confirm Checkout'),
                ),
              ],
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('$docType - $residentName', overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(
                  child: residentId != null && residentId.isNotEmpty
                      ? FutureBuilder<Uint8List?>(
                          future: AdminApiService.getKycDocumentBytes(residentId, docKey ?? 'aadhaar_front'),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                            }
                            if (snapshot.hasData && snapshot.data != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  snapshot.data!,
                                  height: 220,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                ),
                              );
                            }
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.document_scanner_outlined, size: 50, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text('Verified $docType Image', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('Uploaded by resident', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            );
                          },
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.document_scanner_outlined, size: 50, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text('Verified $docType Image', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Uploaded by resident', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _ResidentsScreenState extends State<ResidentsScreen> {
  List<Map<String, dynamic>> get _residents => AppData.residents;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedResidentStatus = 'All Resident Statuses';
  String _selectedKycStatus = 'All KYC Statuses';

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

      if (_selectedKycStatus != 'All KYC Statuses') {
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
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text('KYC: ${resident['name']}', overflow: TextOverflow.ellipsis),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isVerified) ...[
                  const Center(
                    child: Column(
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 60),
                        SizedBox(height: 8),
                        Text('KYC Fully Verified', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ] else if (isRejected) ...[
                  const Center(
                    child: Column(
                      children: [
                        Icon(Icons.cancel, color: Colors.red, size: 60),
                        SizedBox(height: 8),
                        Text('KYC Rejected', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        Text('Please ask resident to re-upload.', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                      ],
                    ),
                  ),
                ] else ...[
                  const Text('Aadhaar Card', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  FutureBuilder<Uint8List?>(
                    future: resId.isNotEmpty ? AdminApiService.getKycDocumentBytes(resId, 'aadhaar_front') : Future.value(null),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.inputBorder),
                          ),
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (snapshot.hasData && snapshot.data != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(snapshot.data!, height: 180, width: double.infinity, fit: BoxFit.cover),
                        );
                      }
                      return Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.inputBorder),
                        ),
                        child: const Center(child: Text('Aadhaar Image (Uploaded by Resident)')),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('PAN Card', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  FutureBuilder<Uint8List?>(
                    future: resId.isNotEmpty ? AdminApiService.getKycDocumentBytes(resId, 'pan_card') : Future.value(null),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.inputBorder),
                          ),
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (snapshot.hasData && snapshot.data != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(snapshot.data!, height: 180, width: double.infinity, fit: BoxFit.cover),
                        );
                      }
                      return Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.inputBorder),
                        ),
                        child: const Center(child: Text('PAN Image (Uploaded by Resident)')),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close', style: TextStyle(color: AppTheme.textGrey)),
            ),
            if (!isVerified) ...[
              ElevatedButton(
                onPressed: () {
                  final reasonController = TextEditingController();
                  String? err;
                  showDialog(
                    context: context,
                    builder: (rCtx) => StatefulBuilder(
                      builder: (dialogContext, setRState) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        title: const Text('Reject KYC Verification'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Please provide a reason for rejecting KYC documents:',
                              style: TextStyle(fontSize: 13, color: AppTheme.textDark),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: reasonController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'e.g. Identity document is unclear or expired',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            if (err != null) ...[
                              const SizedBox(height: 8),
                              Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(rCtx), child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () async {
                              final notes = reasonController.text.trim();
                              if (notes.isEmpty) {
                                setRState(() => err = 'Please enter a valid rejection reason.');
                                return;
                              }
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
                                const SnackBar(content: Text('KYC Rejected! Resident notified.'), backgroundColor: Colors.red),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Reject KYC'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Reject'),
              ),
              ElevatedButton(
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
                    const SnackBar(content: Text('KYC Verified Successfully!'), backgroundColor: Colors.green),
                  );
                },
                child: const Text('Verify Documents'),
              ),
            ]
          ],
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

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final titleSection = const Text('Residents & KYC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark));

              final addBtn = ElevatedButton.icon(
                onPressed: _showAddResidentDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Resident'),
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
                  Expanded(child: titleSection),
                  const SizedBox(width: 16),
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
                  items: const ['All KYC Statuses', 'Verified', 'Pending', 'Rejected'],
                  onChanged: (v) => setState(() => _selectedKycStatus = v),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: residentStatusDropdown),
                          const SizedBox(width: 10),
                          Expanded(child: kycStatusDropdown),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    SizedBox(width: 185, child: residentStatusDropdown),
                    const SizedBox(width: 12),
                    SizedBox(width: 175, child: kycStatusDropdown),
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
          ),
        ],
      ),
    );
  }
}