import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/widgets/table_components.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/app_dropdown.dart';
import 'create_test_invoice_dialog.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  // Shared Invoices from AppData
  List<Map<String, dynamic>> get _invoices => AppData.invoices;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_loadInvoicesFromApi);
    _loadInvoicesFromApi();
  }

  void _loadInvoicesFromApi() async {
    final propId = AppData.selectedPropertyId;
    try {
      final invs = await AdminApiService.getInvoices(propertyId: propId);
      if (invs.isNotEmpty && mounted) {
        setState(() {
          AppData.invoices = invs.map((i) => <String, dynamic>{
            'id': i['id']?.toString() ?? '',
            'name': i['resident_name'] ?? 'Resident',
            'phone': i['resident_phone'] ?? '',
            'room': i['room_number'] ?? '101',
            'property': i['property_name'] ?? AppData.selectedProperty,
            'amount': i['amount'] != null ? (i['amount'] as num).toDouble() : 0.0,
            'expected': i['amount'] != null ? (i['amount'] as num).toDouble() : 0.0,
            'paid': i['paid_amount'] != null ? (i['paid_amount'] as num).toDouble() : 0.0,
            'status': i['status'] == 'PAID' ? 'Paid' : (i['status'] == 'PARTIALLY_PAID' ? 'Partial' : 'Unpaid'),
            'month': i['billing_month'] ?? (i['due_date']?.toString().substring(0, 7)) ?? '2026-11',
            'due_date': i['due_date']?.toString() ?? '',
            'ref_id': i['invoice_number'] ?? i['reference_number'] ?? '',
            'payment_mode': i['payment_mode'] ?? 'UPI',
            'invoice_type': i['invoice_type'] ?? 'RENT',
            'notes': i['notes'],
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('API getInvoices error: $e');
    }
  }
  String _searchQuery = '';
  String _selectedMonth = 'September 2026';
  String _selectedStatus = 'All Payment Statuses';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredInvoices {
    return _invoices.where((inv) {
      final query = _searchQuery.toLowerCase().trim();
      if (query.isNotEmpty) {
        final name = (inv['name'] ?? '').toString().toLowerCase();
        final phone = (inv['phone'] ?? '').toString().toLowerCase();
        final room = (inv['room'] ?? '').toString().toLowerCase();
        final property = (inv['property'] ?? '').toString().toLowerCase();
        final id = (inv['id'] ?? '').toString().toLowerCase();
        final ref = (inv['ref_id'] ?? '').toString().toLowerCase();
        if (!name.contains(query) &&
            !phone.contains(query) &&
            !room.contains(query) &&
            !property.contains(query) &&
            !id.contains(query) &&
            !ref.contains(query)) {
          return false;
        }
      }

      if (_selectedMonth != 'All Months') {
        String monthCode = '2026-09';
        if (_selectedMonth == 'November 2026') monthCode = '2026-11';
        if (_selectedMonth == 'October 2026') monthCode = '2026-10';
        if (_selectedMonth == 'August 2026') monthCode = '2026-08';
        if (_selectedMonth == 'July 2026') monthCode = '2026-07';

        final invMonth = (inv['month'] ?? '').toString();
        if (invMonth.isNotEmpty && invMonth != monthCode) {
          return false;
        }
      }

      if (_selectedStatus != 'All Payment Statuses') {
        final status = (inv['status'] ?? '').toString().trim();
        if (status.toLowerCase() != _selectedStatus.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildPaymentStatusDot(String status) {
    Color dotColor;
    if (status.toLowerCase() == 'paid') {
      dotColor = const Color(0xFF10B981);
    } else if (status.toLowerCase() == 'partial') {
      dotColor = const Color(0xFFF59E0B);
    } else if (status.toLowerCase() == 'overdue') {
      dotColor = const Color(0xFFEF4444);
    } else {
      dotColor = const Color(0xFF94A3B8);
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

  String _formatCurrency(num val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final totalExpected = _invoices.fold<num>(0, (sum, i) => sum + (i['expected'] as num? ?? i['amount'] as num? ?? 0));
    final totalCollected = _invoices.fold<num>(0, (sum, i) => sum + (i['paid'] as num? ?? (i['status'] == 'Paid' ? (i['amount'] as num? ?? 0) : 0)));
    final pendingDues = _invoices.where((i) => i['status'] == 'Pending' || i['status'] == 'Partial').fold<num>(0, (sum, i) {
      final exp = i['expected'] as num? ?? i['amount'] as num? ?? 0;
      final pd = i['paid'] as num? ?? 0;
      return sum + (exp - pd);
    });
    final overdueRent = _invoices.where((i) => i['status'] == 'Overdue').fold<num>(0, (sum, i) {
      final exp = i['expected'] as num? ?? i['amount'] as num? ?? 0;
      final pd = i['paid'] as num? ?? 0;
      return sum + (exp - pd);
    });

    final filtered = _filteredInvoices;

    return LayoutBuilder(
      builder: (context, screenConstraints) {
        final isCompact = screenConstraints.maxWidth < 700 || screenConstraints.maxHeight < 650;
        final mainContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header Row with Title and "Create Test Invoice" button
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 560;
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rent & Payments', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => CreateTestInvoiceDialog.show(
                          context,
                          onInvoiceCreated: _loadInvoicesFromApi,
                        ),
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text('Create Test Invoice'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Rent & Payments', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                  ElevatedButton.icon(
                    onPressed: () => CreateTestInvoiceDialog.show(
                      context,
                      onInvoiceCreated: _loadInvoicesFromApi,
                    ),
                    icon: const Icon(Icons.add_task_rounded, size: 18),
                    label: const Text('Create Test Invoice'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // 1. Top Summary Row (4 Summary Cards)
          TableKpiGrid(
            cards: [
              TableKpiCard(
                title: 'Total Expected',
                value: '₹ ${_formatCurrency(totalExpected)}',
                subtitle: 'All billed properties',
                icon: Icons.account_balance_wallet_outlined,
                iconColor: const Color(0xFF7C3AED), // Purple icon
                iconBgColor: const Color(0xFFF5F3FF),
              ),
              TableKpiCard(
                title: 'Total Collected',
                value: '₹ ${_formatCurrency(totalCollected)}',
                subtitle: 'Verified receipts',
                icon: Icons.check_circle_outline, // Green check icon
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              ),
              TableKpiCard(
                title: 'Pending Dues',
                value: '₹ ${_formatCurrency(pendingDues)}',
                subtitle: 'Awaiting clearance',
                icon: Icons.access_time_outlined, // Orange clock icon
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFFFBEB),
              ),
              TableKpiCard(
                title: 'Overdue Rent',
                value: '₹ ${_formatCurrency(overdueRent)}',
                subtitle: 'Action required',
                icon: Icons.warning_amber_rounded, // Red warning icon
                iconColor: const Color(0xFFDC2626),
                iconBgColor: const Color(0xFFFEF2F2),
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
                    hintText: 'Search resident, room, phone...',
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

                final monthDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedMonth,
                  leadingIcon: Icons.calendar_month_outlined,
                  items: const ['All Months', 'November 2026', 'October 2026', 'September 2026', 'August 2026', 'July 2026'],
                  onChanged: (v) => setState(() => _selectedMonth = v),
                );

                final statusDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedStatus,
                  items: const ['All Payment Statuses', 'Paid', 'Pending', 'Partial', 'Overdue'],
                  onChanged: (v) => setState(() => _selectedStatus = v),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: monthDropdown),
                          const SizedBox(width: 10),
                          Expanded(child: statusDropdown),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    SizedBox(width: 185, child: monthDropdown),
                    const SizedBox(width: 12),
                    SizedBox(width: 185, child: statusDropdown),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. Invoice Table
          Builder(
            builder: (context) {
              final tableBox = Container(
                decoration: modernTableDecoration,
                child: filtered.isEmpty
                    ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No invoices found',
                      subtitle: _searchQuery.isNotEmpty || _selectedStatus != 'All Payment Statuses'
                          ? 'Try adjusting your search or filters'
                          : 'No rent transactions found for this period',
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
                                  modernTableColumn('RESIDENT'),
                                  modernTableColumn('PROPERTY'),
                                  modernTableColumn('ROOM'),
                                  modernTableColumn('MONTH'),
                                  modernTableColumn('EXPECTED'),
                                  modernTableColumn('PAID'),
                                  modernTableColumn('STATUS'),
                                  modernTableColumn('PAYMENT MODE & REF'),
                                  modernTableColumn('ACTION'),
                                ],
                                rows: filtered.map((inv) {
                                  final invoiceIndex = _invoices.indexOf(inv);
                                  final isPaid = inv['status'] == 'Paid';
                                  final num expected = inv['expected'] as num? ?? inv['amount'] as num? ?? 0;
                                  final num paid = inv['paid'] as num? ?? (isPaid ? expected : 0);
                                  final isTest = (inv['invoice_type'] ?? '').toString().startsWith('TEST');

                                  return DataRow(cells: [
                                    // RESIDENT (Avatar + Name + Phone)
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableAvatar(name: inv['name'] ?? 'R', radius: 17),
                                          const SizedBox(width: 12),
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                inv['name'] ?? '', 
                                                style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold, fontSize: 14),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (inv['phone'] != null)
                                                Text(
                                                  inv['phone'], 
                                                  style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // PROPERTY
                                    DataCell(
                                      Text(
                                        inv['property'] ?? 'Green View PG - Hebbal',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    // ROOM
                                    DataCell(
                                      Text(
                                        inv['room'] != null && inv['room'].toString().startsWith('Room')
                                            ? inv['room'].toString()
                                            : 'Room ${inv['room'] ?? '101'}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                                      ),
                                    ),
                                    // MONTH
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            inv['month'] ?? '2026-09',
                                            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, fontWeight: FontWeight.w500),
                                          ),
                                          if (isTest) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFF3B82F6), width: 0.8),
                                              ),
                                              child: const Text(
                                                'TEST',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF1D4ED8),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    // EXPECTED
                                    DataCell(
                                      Text(
                                        '₹ ${_formatCurrency(expected)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 13),
                                      ),
                                    ),
                                    // PAID
                                    DataCell(
                                      Text(
                                        '₹ ${_formatCurrency(paid)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isPaid ? const Color(0xFF059669) : AppTheme.textDark,
                                        ),
                                      ),
                                    ),
                                    // STATUS (Green dot Paid, Orange dot Partial, Grey dot Pending, Red dot Overdue)
                                    DataCell(
                                      _buildPaymentStatusDot(inv['status'] ?? 'Pending'),
                                    ),
                                    // PAYMENT MODE & REF
                                    DataCell(
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            inv['payment_mode'] ?? (isPaid ? 'UPI' : '-'),
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textDark),
                                          ),
                                          Text(
                                            inv['ref_id'] ?? '-',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textGrey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // ACTION (Receipt button if paid, Collect button if pending)
                                    DataCell(
                                      isPaid
                                          ? OutlinedButton.icon(
                                              onPressed: () async {
                                                final receiptId = inv['receipt_id']?.toString() ?? inv['id']?.toString();
                                                if (receiptId != null && receiptId.isNotEmpty && !receiptId.startsWith('inv-')) {
                                                  try {
                                                    final bytes = await AdminApiService.downloadReceiptPdf(receiptId);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text('Receipt PDF generated (${bytes.length} bytes) for ${inv['name']}!'),
                                                          backgroundColor: const Color(0xFF059669),
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  } catch (e) {
                                                    debugPrint('API downloadReceiptPdf info: $e');
                                                  }
                                                }
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Receipt viewed for ${inv['name']} (${inv['id'] ?? 'INV'})'),
                                                      backgroundColor: AppTheme.primaryBlue,
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(Icons.receipt_outlined, size: 14, color: AppTheme.primaryBlue),
                                              label: const Text('Receipt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: Color(0xFFBFDBFE)),
                                                backgroundColor: const Color(0xFFEFF6FF),
                                                minimumSize: const Size(0, 32),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              onPressed: () => _showRecordPaymentModal(context, inv, invoiceIndex),
                                              icon: const Icon(Icons.check, size: 14, color: Colors.white),
                                              label: const Text('Collect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF059669),
                                                foregroundColor: Colors.white,
                                                minimumSize: const Size(0, 32),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                elevation: 0,
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
              );

              return isCompact
                  ? SizedBox(height: 380, child: tableBox)
                  : Expanded(child: tableBox);
            },
          ),
        ],
      );

      if (isCompact) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: mainContent,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: mainContent,
      );
    },
  );
}

  // Modal to record offline payment (Cash/UPI)
  void _showRecordPaymentModal(BuildContext context, Map<String, dynamic> invoice, int index) {
    String selectedMethod = 'UPI';
    final amountController = TextEditingController(
      text: ((invoice['expected'] ?? invoice['amount'] ?? 8000) - (invoice['paid'] ?? 0)).toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Collect Payment: ${invoice['name']}', overflow: TextOverflow.ellipsis),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Property: ${invoice['property'] ?? 'Green View PG - Hebbal'}', style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Room: ${invoice['room'] ?? '101'} • Month: ${invoice['month'] ?? '2026-09'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Collect Amount (₹)',
                        prefixText: '₹ ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMethod,
                      decoration: const InputDecoration(labelText: 'Payment Mode'),
                      items: ['UPI', 'Cash', 'Bank Transfer'].map((String method) {
                        return DropdownMenuItem(value: method, child: Text(method));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedMethod = val);
                      },
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
                    final enteredAmount = int.tryParse(amountController.text) ?? (invoice['expected'] ?? 8000);
                    final invId = invoice['id']?.toString();
                    if (invId != null && invId.isNotEmpty && !invId.startsWith('inv-')) {
                      try {
                        await AdminApiService.collectPayment(
                          invoiceId: invId,
                          amount: enteredAmount.toDouble(),
                          paymentMode: selectedMethod.toUpperCase().replaceAll(' ', '_'),
                          referenceNumber: 'REF-${DateTime.now().millisecondsSinceEpoch}',
                        );
                        _loadInvoicesFromApi();
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to record payment: $e'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }
                    }
                    if (!mounted) return;
                    setState(() {
                      _invoices[index]['status'] = 'Paid';
                      _invoices[index]['paid'] = enteredAmount;
                      _invoices[index]['payment_mode'] = selectedMethod;
                      _invoices[index]['ref_id'] = selectedMethod == 'UPI' ? 'TXN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}' : 'CSH-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Payment of ₹ $enteredAmount collected for ${invoice['name']}!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                  child: const Text('Confirm Payment'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
