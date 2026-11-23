import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_dialogs.dart';

class CreateTestInvoiceDialog extends StatefulWidget {
  final VoidCallback onInvoiceCreated;

  const CreateTestInvoiceDialog({super.key, required this.onInvoiceCreated});

  static Future<void> show(BuildContext context, {required VoidCallback onInvoiceCreated}) {
    // Role check: Only SUPER_ADMIN and PROPERTY_MANAGER roles can create invoices
    if (!TokenStorage.canManageInvoices) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: Only SUPER_ADMIN and PROPERTY_MANAGER roles can create test invoices.'),
          backgroundColor: Color(0xFFDC2626),
          duration: Duration(seconds: 4),
        ),
      );
      return Future.value();
    }

    return showPremiumDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CreateTestInvoiceDialog(onInvoiceCreated: onInvoiceCreated),
    );
  }

  @override
  State<CreateTestInvoiceDialog> createState() => _CreateTestInvoiceDialogState();
}

class _CreateTestInvoiceDialogState extends State<CreateTestInvoiceDialog> {
  bool _isLoading = false;
  bool _isFetchingResidents = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _properties = [];
  String? _selectedPropertyId;
  String? _selectedPropertyName;

  List<Map<String, dynamic>> _residents = [];
  String? _selectedResidentId;
  String? _selectedResidentName;

  DateTime _selectedDueDate = DateTime.now();
  late final TextEditingController _notesController;

  static const double testAmount = 1.00;
  static const String testInvoiceType = 'TEST';

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: '₹1 UPI Integration Test Invoice');
    _loadProperties();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> props = await AdminApiService.getProperties();
      if (props.isEmpty) {
        props = AppData.properties;
      }
      if (mounted) {
        setState(() {
          _properties = props;
          final currentId = AppData.selectedPropertyId;
          if (currentId != null && props.any((p) => p['id']?.toString() == currentId)) {
            _selectedPropertyId = currentId;
            final match = props.firstWhere((p) => p['id']?.toString() == currentId);
            _selectedPropertyName = match['name']?.toString() ?? 'Selected Property';
          } else if (props.isNotEmpty) {
            _selectedPropertyId = props.first['id']?.toString();
            _selectedPropertyName = props.first['name']?.toString() ?? 'Selected Property';
          }
          _isLoading = false;
        });

        if (_selectedPropertyId != null) {
          _loadResidentsForProperty(_selectedPropertyId!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _properties = AppData.properties;
          if (_properties.isNotEmpty) {
            _selectedPropertyId = _properties.first['id']?.toString();
            _selectedPropertyName = _properties.first['name']?.toString();
          }
          _isLoading = false;
        });
        if (_selectedPropertyId != null) {
          _loadResidentsForProperty(_selectedPropertyId!);
        }
      }
    }
  }

  Future<void> _loadResidentsForProperty(String propertyId) async {
    setState(() {
      _isFetchingResidents = true;
      _selectedResidentId = null;
      _selectedResidentName = null;
      _errorMessage = null;
    });

    try {
      final resList = await AdminApiService.getResidents(propertyId: propertyId, status: 'ACTIVE');
      if (mounted) {
        setState(() {
          _residents = resList;
          if (_residents.isNotEmpty) {
            _selectedResidentId = _residents.first['id']?.toString();
            _selectedResidentName = _getResidentName(_residents.first);
          }
          _isFetchingResidents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _residents = [];
          _isFetchingResidents = false;
        });
      }
    }
  }

  String _getResidentName(Map<String, dynamic> r) {
    if (r['name'] != null && r['name'].toString().isNotEmpty) return r['name'].toString();
    if (r['user'] != null && r['user']['full_name'] != null) return r['user']['full_name'].toString();
    if (r['full_name'] != null && r['full_name'].toString().isNotEmpty) return r['full_name'].toString();
    return 'Resident ${r['id']?.toString().substring(0, 6) ?? ''}';
  }

  String _getResidentLabel(Map<String, dynamic> r) {
    final name = _getResidentName(r);
    final room = r['room'] ?? r['room_number'] ?? r['bed']?['room']?['room_number'] ?? r['bed_number'];
    final roomStr = room != null ? 'Room $room' : 'Unallocated';
    final phone = r['phone'] ?? r['user']?['phone'];
    final phoneStr = phone != null ? ' • $phone' : '';
    return '$name ($roomStr$phoneStr)';
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              onSurface: AppTheme.textDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDueDate = picked);
    }
  }

  void _onConfirmAndSubmit() {
    if (_selectedPropertyId == null || _selectedPropertyId!.isEmpty) {
      setState(() => _errorMessage = 'Please select a valid property.');
      return;
    }
    if (_selectedResidentId == null || _selectedResidentId!.isEmpty) {
      setState(() => _errorMessage = 'Please select a resident to issue the test invoice to.');
      return;
    }

    final dueDateStr = '${_selectedDueDate.year}-${_selectedDueDate.month.toString().padLeft(2, '0')}-${_selectedDueDate.day.toString().padLeft(2, '0')}';
    final billingMonth = dueDateStr.substring(0, 7);

    showPremiumConfirmDialog(
      context: context,
      title: 'Confirm Test Invoice',
      subtitle: 'Safe ₹1.00 UPI verification invoice',
      message: 'Are you sure you want to create a ₹1.00 test invoice for $_selectedResidentName?',
      confirmLabel: 'Confirm & Create',
      confirmColor: AppTheme.primaryTeal,
      icon: Icons.receipt_long_rounded,
      details: [
        {'label': 'Property', 'value': _selectedPropertyName ?? 'PG Property'},
        {'label': 'Resident', 'value': _selectedResidentName ?? 'Resident'},
        {'label': 'Amount', 'value': '₹ 1.00'},
        {'label': 'Due Date', 'value': dueDateStr},
        {'label': 'Type', 'value': testInvoiceType},
      ],
      onConfirm: () async {
        await _submitInvoice(billingMonth: billingMonth, dueDateStr: dueDateStr);
      },
    );
  }

  Future<void> _submitInvoice({required String billingMonth, required String dueDateStr}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await AdminApiService.createInvoice(
        propertyId: _selectedPropertyId!,
        residentId: _selectedResidentId!,
        amount: testAmount,
        billingMonth: billingMonth,
        dueDate: dueDateStr,
        invoiceType: testInvoiceType,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      final invNumber = res['invoice_number'] ?? res['id'] ?? 'INV-TEST';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);

      widget.onInvoiceCreated();

      messenger.showSnackBar(
        SnackBar(
          content: Text('Test invoice \'$invNumber\' of ₹ 1.00 created successfully for $_selectedResidentName!'),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dueDateStr = '${_selectedDueDate.year}-${_selectedDueDate.month.toString().padLeft(2, '0')}-${_selectedDueDate.day.toString().padLeft(2, '0')}';

    return PremiumDialog(
      maxWidth: 480,
      title: 'Create Test Invoice',
      subtitle: 'Safe ₹1.00 UPI verification invoice',
      icon: Icons.receipt_long_rounded,
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
        ),
        ElevatedButton.icon(
          onPressed: (_isLoading || _selectedResidentId == null) ? null : _onConfirmAndSubmit,
          icon: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_isLoading ? 'Creating...' : 'Create Test Invoice'),
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
          // Notice banner
          const PremiumDialogBanner(
            message: 'Generates an isolated ₹1.00 test invoice for real UPI app integration testing. Existing rent and billing records remain untouched.',
            type: BannerType.warning,
          ),
          const SizedBox(height: 18),

          if (_errorMessage != null) ...[
            PremiumDialogBanner(
              message: _errorMessage!,
              type: BannerType.error,
            ),
            const SizedBox(height: 14),
          ],

          // 1. Select Property
          const Text('Property', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedPropertyId,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5)),
            ),
            items: _properties.map((prop) {
              final id = prop['id']?.toString() ?? '';
              final name = prop['name']?.toString() ?? 'PG Property';
              return DropdownMenuItem<String>(
                value: id,
                child: Text(name, style: const TextStyle(fontSize: 13, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: _isLoading
                ? null
                : (val) {
                    if (val != null && val != _selectedPropertyId) {
                      setState(() {
                        _selectedPropertyId = val;
                        final match = _properties.firstWhere((p) => p['id']?.toString() == val, orElse: () => {});
                        _selectedPropertyName = match['name']?.toString();
                      });
                      _loadResidentsForProperty(val);
                    }
                  },
          ),
          const SizedBox(height: 16),

          // 2. Select Resident
          const Text('Resident', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          if (_isFetchingResidents) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal)),
              ),
            ),
          ] else if (_residents.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text('No active residents found in this property.', style: TextStyle(fontSize: 12.5, color: AppTheme.textGrey)),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedResidentId,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5)),
              ),
              items: _residents.map((r) {
                final id = r['id']?.toString() ?? '';
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(_getResidentLabel(r), style: const TextStyle(fontSize: 13, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedResidentId = val;
                    final match = _residents.firstWhere((r) => r['id']?.toString() == val, orElse: () => {});
                    _selectedResidentName = _getResidentName(match);
                  });
                }
              },
            ),
          ],
          const SizedBox(height: 16),

          // 3. Amount (Fixed ₹1.00) & Invoice Type (TEST)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Amount', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: const Row(
                        children: [
                          Text('₹ 1.00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF059669))),
                          SizedBox(width: 8),
                          Text('(Fixed)', style: TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Invoice Type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text('TEST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF475569))),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Due Date
          const Text('Due Date', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDueDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dueDateStr, style: const TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                  const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primaryTeal),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 5. Notes
          const Text('Notes', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 6),
          TextField(
            controller: _notesController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}
