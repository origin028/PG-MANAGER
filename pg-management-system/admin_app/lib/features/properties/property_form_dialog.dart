import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';

Future<void> showAddEditPropertyDialog({
  required BuildContext context,
  Map<String, dynamic>? property,
  VoidCallback? onSaved,
  VoidCallback? onDeleted,
}) async {
  final isEdit = property != null;
  final propertyId = isEdit ? (property['id'] ?? 'p1').toString() : 'p${AppData.properties.length + 1}';

  final nameController = TextEditingController(text: isEdit ? property['name']?.toString() : '');
  final addressController = TextEditingController(text: isEdit ? property['address']?.toString() : '');
  final cityController = TextEditingController(text: isEdit ? property['city']?.toString() : 'Bengaluru');
  final pincodeController = TextEditingController(text: isEdit ? property['pincode']?.toString() : '');

  final ownerNameController = TextEditingController(text: isEdit ? property['ownerName']?.toString() : '');
  final ownerContactController = TextEditingController(text: isEdit ? property['ownerContact']?.toString() : '');
  final ownerEmailController = TextEditingController(text: isEdit ? property['ownerEmail']?.toString() : '');
  final managerNameController = TextEditingController(text: isEdit ? property['managerName']?.toString() : '');
  final managerContactController = TextEditingController(text: isEdit ? property['managerContact']?.toString() : '');

  final floorsController = TextEditingController(text: isEdit ? (property['floors'] ?? 3).toString() : '3');
  final roomsController = TextEditingController(text: isEdit ? (property['rooms'] ?? 10).toString() : '10');
  final bedsController = TextEditingController(text: isEdit ? (property['beds'] ?? 18).toString() : '18');

  const propertyTypes = ['PG', 'Hostel', 'Flat'];
  const occupancyTypes = ['Boys', 'Girls', 'Co-Living'];

  const availableAmenities = [
    'High Speed Wi-Fi',
    '3 Times Daily Meals',
    'Washing Machine',
    'Daily Housekeeping',
    'RO Drinking Water',
    'CCTV & Biometric Security',
    '24/7 Power Backup',
    'Common Lounge & TV',
    'AC / Cooler',
    'Parking',
  ];

  final List<String> selectedAmenities = isEdit && property['amenities'] is List
      ? List<String>.from((property['amenities'] as List).map((e) {
          final s = e.toString();
          if (s == 'WiFi') return 'High Speed Wi-Fi';
          if (s == 'Power Backup') return '24/7 Power Backup';
          if (s == 'AC') return 'AC / Cooler';
          if (s == 'Food / Mess') return '3 Times Daily Meals';
          if (s == 'Daily Cleaning') return 'Daily Housekeeping';
          if (s == 'CCTV') return 'CCTV & Biometric Security';
          return s;
        }))
      : [
          'High Speed Wi-Fi',
          '3 Times Daily Meals',
          'Daily Housekeeping',
          'RO Drinking Water',
          '24/7 Power Backup',
        ];

  String propertyType = isEdit ? (property['propertyType'] ?? 'PG').toString() : 'PG';
  if (!propertyTypes.contains(propertyType)) propertyType = 'PG';

  String occupancyType = isEdit
      ? (property['occupancyType'] ?? (property['type'] == 'Girls PG' ? 'Girls' : property['type'] == 'Boys PG' ? 'Boys' : 'Co-Living')).toString()
      : 'Boys';
  if (!occupancyTypes.contains(occupancyType)) occupancyType = 'Boys';

  InputDecoration propertyInputDecoration({String? hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.0),
      ),
    );
  }

  Widget buildFieldLabel(String label, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildPropertyDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B), size: 20),
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFF4338CA),
        letterSpacing: -0.2,
      ),
    );
  }

  void showDeleteConfirmDialog(BuildContext parentContext, BuildContext dialogContext, Map<String, dynamic> prop) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Property?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to permanently delete "${prop['name']}"? This action cannot be undone.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pid = prop['id']?.toString() ?? '';
              if (pid.isNotEmpty && !pid.startsWith('p')) {
                try {
                  await AdminApiService.deleteProperty(pid);
                } catch (e) {
                  if (parentContext.mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(content: Text('Failed to delete property: $e'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              AppData.properties.removeWhere((p) =>
                  (p['id'] != null && p['id'] == prop['id']) || p['name'] == prop['name']);
              AppData.propertyNames.removeWhere((name) => name == prop['name']);
              if (AppData.selectedProperty == prop['name'] && AppData.propertyNames.isNotEmpty) {
                AppData.selectedProperty = AppData.propertyNames.first;
              }
              onDeleted?.call();
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text('${prop['name']} deleted successfully!'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete Property', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  await showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 850),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Row with Title and Close Icon
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isEdit ? 'Edit Property Details' : 'Add New Property',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

                  // Scrollable Form Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Property ID small grey text
                          Text(
                            'Property ID: $propertyId',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ========================================================
                          // SECTION 1: BASIC PROPERTY INFORMATION
                          // ========================================================
                          buildSectionHeader('1. Basic Property Information'),
                          const SizedBox(height: 14),

                          // Row 1: Property Name * | Property Type *
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 520;
                              final nameField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Property Name', isRequired: true),
                                  TextField(
                                    controller: nameController,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. Silicon Oasis PG - HSR Layout'),
                                  ),
                                ],
                              );
                              final typeField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Property Type', isRequired: true),
                                  buildPropertyDropdown(
                                    value: propertyType,
                                    items: propertyTypes,
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => propertyType = val);
                                    },
                                  ),
                                ],
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    nameField,
                                    const SizedBox(height: 12),
                                    typeField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: nameField),
                                  const SizedBox(width: 16),
                                  Expanded(flex: 2, child: typeField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),

                          // Row 2: Property Address * (Full width)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              buildFieldLabel('Property Address', isRequired: true),
                              TextField(
                                controller: addressController,
                                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                decoration: propertyInputDecoration(hintText: 'e.g. Sector 2, 27th Main Rd, HSR Layout'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Row 3: City * | Pincode | Occupancy Type * (3 Columns)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 520;
                              final cityField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('City', isRequired: true),
                                  TextField(
                                    controller: cityController,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. Bengaluru'),
                                  ),
                                ],
                              );
                              final pincodeField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Pincode'),
                                  TextField(
                                    controller: pincodeController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. 560102'),
                                  ),
                                ],
                              );
                              final occupancyField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Occupancy Type', isRequired: true),
                                  buildPropertyDropdown(
                                    value: occupancyType,
                                    items: occupancyTypes,
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => occupancyType = val);
                                    },
                                  ),
                                ],
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    cityField,
                                    const SizedBox(height: 12),
                                    pincodeField,
                                    const SizedBox(height: 12),
                                    occupancyField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: cityField),
                                  const SizedBox(width: 14),
                                  Expanded(flex: 2, child: pincodeField),
                                  const SizedBox(width: 14),
                                  Expanded(flex: 3, child: occupancyField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // ========================================================
                          // SECTION 2: OWNER / MANAGER DETAILS
                          // ========================================================
                          buildSectionHeader('2. Owner / Manager Details'),
                          const SizedBox(height: 14),

                          // Row 1: Owner Name * | Owner Contact Number *
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 520;
                              final ownerNameField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Owner Name', isRequired: true),
                                  TextField(
                                    controller: ownerNameController,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. Arun Sharma'),
                                  ),
                                ],
                              );
                              final ownerContactField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Owner Contact Number', isRequired: true),
                                  TextField(
                                    controller: ownerContactController,
                                    keyboardType: TextInputType.phone,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. 9876543210'),
                                  ),
                                ],
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    ownerNameField,
                                    const SizedBox(height: 12),
                                    ownerContactField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: ownerNameField),
                                  const SizedBox(width: 16),
                                  Expanded(child: ownerContactField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),

                          // Row 2: Owner Email (Full width)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              buildFieldLabel('Owner Email'),
                              TextField(
                                controller: ownerEmailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                decoration: propertyInputDecoration(hintText: 'e.g. owner@example.com'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Row 3: Property Manager Name | Property Manager Contact Number
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 520;
                              final managerNameField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Property Manager Name'),
                                  TextField(
                                    controller: managerNameController,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. Manjunath'),
                                  ),
                                ],
                              );
                              final managerContactField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Property Manager Contact Number'),
                                  TextField(
                                    controller: managerContactController,
                                    keyboardType: TextInputType.phone,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. 9876543221'),
                                  ),
                                ],
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    managerNameField,
                                    const SizedBox(height: 12),
                                    managerContactField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: managerNameField),
                                  const SizedBox(width: 16),
                                  Expanded(child: managerContactField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // ========================================================
                          // SECTION 3: PROPERTY STRUCTURE
                          // ========================================================
                          buildSectionHeader('3. Property Structure'),
                          const SizedBox(height: 14),

                          // Row 1: Number of Floors * | Total Rooms * | Total Beds / Capacity * (3 Columns)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 520;
                              final floorsField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Number of Floors', isRequired: true),
                                  TextField(
                                    controller: floorsController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. 3'),
                                  ),
                                ],
                              );
                              final roomsField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Total Rooms', isRequired: true),
                                  TextField(
                                    controller: roomsController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. 10'),
                                  ),
                                ],
                              );
                              final bedsField = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildFieldLabel('Total Beds / Capacity', isRequired: true),
                                  TextField(
                                    controller: bedsController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                    decoration: propertyInputDecoration(hintText: 'e.g. 18'),
                                  ),
                                ],
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    floorsField,
                                    const SizedBox(height: 12),
                                    roomsField,
                                    const SizedBox(height: 12),
                                    bedsField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: floorsField),
                                  const SizedBox(width: 16),
                                  Expanded(child: roomsField),
                                  const SizedBox(width: 16),
                                  Expanded(child: bedsField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // ========================================================
                          // SECTION 4: AMENITIES & INCLUSIONS
                          // ========================================================
                          buildSectionHeader('4. Amenities & Inclusions'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: availableAmenities.map((amenity) {
                              final isSelected = selectedAmenities.contains(amenity);
                              return FilterChip(
                                label: Text(amenity),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      selectedAmenities.add(amenity);
                                    } else {
                                      selectedAmenities.remove(amenity);
                                    }
                                  });
                                },
                                selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                                checkmarkColor: const Color(0xFF4F46E5),
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF334155),
                                ),
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

                  // ========================================================
                  // PINNED FOOTER / ACTION BUTTONS (Matches Screenshot)
                  // ========================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: LayoutBuilder(
                      builder: (context, footerConstraints) {
                        final isNarrow = footerConstraints.maxWidth < 440;

                        void onSavePressed() async {
                          final name = nameController.text.trim();
                          final address = addressController.text.trim();
                          final city = cityController.text.trim();
                          final pincode = pincodeController.text.trim();
                          final ownerName = ownerNameController.text.trim();
                          final ownerContact = ownerContactController.text.trim();
                          final ownerEmail = ownerEmailController.text.trim();
                          final managerName = managerNameController.text.trim();
                          final managerContact = managerContactController.text.trim();

                          final floors = int.tryParse(floorsController.text.trim()) ?? 1;
                          final rooms = int.tryParse(roomsController.text.trim()) ?? 10;
                          final beds = int.tryParse(bedsController.text.trim()) ?? 18;

                          // Required field validations
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter Property Name'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (address.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter Property Address'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (city.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter City'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (ownerName.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter Owner Name'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (ownerContact.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter Owner Contact Number'), backgroundColor: Colors.red),
                            );
                            return;
                          }

                          if (property != null) {
                            final pid = property['id']?.toString() ?? propertyId;
                            if (!pid.startsWith('p')) {
                              try {
                                await AdminApiService.updateProperty(pid, {
                                  'name': name,
                                  'code': property['code'] ?? 'PROP_${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase()}',
                                  'address_line1': address,
                                  'address': address,
                                  'city': city,
                                  'pincode': pincode,
                                  'total_floors': floors,
                                });
                              } catch (e) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                                    SnackBar(content: Text('Failed to update property: $e'), backgroundColor: Colors.red),
                                  );
                                }
                                return;
                              }
                            }
                            property['name'] = name;
                            property['propertyType'] = propertyType;
                            property['address'] = address;
                            property['city'] = city;
                            property['pincode'] = pincode;
                            property['occupancyType'] = occupancyType;
                            property['type'] = occupancyType;
                            property['ownerName'] = ownerName;
                            property['ownerContact'] = ownerContact;
                            property['ownerEmail'] = ownerEmail;
                            property['managerName'] = managerName;
                            property['managerContact'] = managerContact;
                            property['floors'] = floors;
                            property['rooms'] = rooms;
                            property['beds'] = beds;
                            property['amenities'] = List<String>.from(selectedAmenities);

                            if (!AppData.propertyNames.contains(name)) {
                              AppData.propertyNames.add(name);
                            }
                            AppData.selectedProperty = name;

                            onSaved?.call();
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$name updated successfully!'), backgroundColor: Colors.green),
                              );
                            }
                          } else {
                            // Check for duplicate name
                            if (AppData.properties.any((p) => p['name'].toString().toLowerCase() == name.toLowerCase())) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(content: Text('A property with this name already exists!'), backgroundColor: Colors.red),
                              );
                              return;
                            }

                            Map<String, dynamic> created = {};
                            try {
                              created = await AdminApiService.createProperty({
                                'name': name,
                                'code': 'PROP_${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase()}',
                                'address_line1': address,
                                'address': address,
                                'city': city,
                                'pincode': pincode,
                                'total_floors': floors,
                                'description': propertyType,
                                'property_type': occupancyType == 'Girls' ? 'GIRLS' : (occupancyType == 'Boys' ? 'BOYS' : 'CO_LIVING'),
                              });
                            } catch (e) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('Failed to add property: $e'), backgroundColor: Colors.red),
                                );
                              }
                              return;
                            }

                            final newProp = {
                              'id': created['id']?.toString() ?? propertyId,
                              'code': created['code']?.toString() ?? 'PROP_${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase()}',
                              'name': name,
                              'propertyType': propertyType,
                              'address': address,
                              'city': city,
                              'pincode': pincode,
                              'occupancyType': occupancyType,
                              'type': occupancyType,
                              'ownerName': ownerName,
                              'ownerContact': ownerContact,
                              'ownerEmail': ownerEmail,
                              'managerName': managerName,
                              'managerContact': managerContact,
                              'floors': floors,
                              'rooms': rooms,
                              'beds': beds,
                              'status': 'Active',
                              'amenities': List<String>.from(selectedAmenities),
                            };
                            AppData.properties.add(newProp);

                            if (!AppData.propertyNames.contains(name)) {
                              AppData.propertyNames.add(name);
                            }
                            AppData.selectedProperty = name;

                            onSaved?.call();
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Property Added Successfully!'), backgroundColor: Colors.green),
                              );
                            }
                          }
                        }

                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(dialogContext),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF374151),
                                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: onSavePressed,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4F46E5),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: Text(
                                        isEdit ? 'Save Changes' : 'Add Property',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isEdit) ...[
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: () => showDeleteConfirmDialog(context, dialogContext, property),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text(
                                    'Delete Property',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ],
                          );
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (isEdit)
                              ElevatedButton(
                                onPressed: () => showDeleteConfirmDialog(context, dialogContext, property),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text(
                                  'Delete Property',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF374151),
                                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: onSavePressed,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4F46E5),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text(
                                    isEdit ? 'Save Changes' : 'Add Property',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
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

  nameController.dispose();
  addressController.dispose();
  cityController.dispose();
  pincodeController.dispose();
  ownerNameController.dispose();
  ownerContactController.dispose();
  ownerEmailController.dispose();
  managerNameController.dispose();
  managerContactController.dispose();
  floorsController.dispose();
  roomsController.dispose();
  bedsController.dispose();
}
