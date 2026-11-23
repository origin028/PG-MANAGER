import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/widgets/table_components.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/widgets/month_year_selector.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  // Shared Invoices from AppData
  List<Map<String, dynamic>> get _invoices => AppData.invoices;
  List<Map<String, dynamic>> _paymentTransactions = [];
  int _activeTabIndex = 0; // 0: Rent Invoices, 1: UPI Reconciliation Queue
  String _upiStatusFilter = 'ALL';

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

    try {
      final txList = await AdminApiService.getPaymentHistory(propertyId: propId);
      if (mounted) {
        setState(() {
          _paymentTransactions = txList;
        });
      }
    } catch (e) {
      debugPrint('API getPaymentHistory error: $e');
    }
  }
  String _searchQuery = '';
  String _selectedMonth = 'November 2026';
  int _selectedMonthNumber = DateTime.now().month;
  int _selectedYearNumber = DateTime.now().year;
  String _selectedStatus = 'All Payment Statuses';

  @override
  void dispose() {
    AppData.selectedPropertyIdNotifier.removeListener(_loadInvoicesFromApi);
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    final query = _searchQuery.toLowerCase().trim();
    return _paymentTransactions.where((tx) {
      final st = (tx['status'] ?? '').toString().toUpperCase();
      if (_upiStatusFilter != 'ALL') {
        if (_upiStatusFilter == 'PENDING' &&
            st != 'PENDING' &&
            st != 'PENDING_VERIFICATION') {
          return false;
        } else if (_upiStatusFilter == 'VERIFIED' &&
            st != 'PAID' &&
            st != 'SUCCESS') {
          return false;
        } else if (_upiStatusFilter == 'FAILED' &&
            st != 'FAILED' &&
            st != 'CANCELLED') {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final combined = [
          tx['resident_name'],
          tx['invoice_number'],
          tx['transaction_ref'],
          tx['bank_reference'],
          tx['client_upi_txn_id'],
          tx['payment_number'],
        ].whereType<Object>().join(' ').toLowerCase();
        if (!combined.contains(query)) return false;
      }
      return true;
    }).toList();
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
          // Header Row
          const Text(
            'Rent & Payments',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
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

          // View Switcher: Rent Invoices vs UPI Reconciliation Queue
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Rent Invoices'),
                selected: _activeTabIndex == 0,
                onSelected: (_) => setState(() => _activeTabIndex = 0),
              ),
              ChoiceChip(
                label: Text(
                  'Verification Queue (${_paymentTransactions.where((t) {
                    final s = (t['status'] ?? '').toString().toUpperCase();
                    return s == 'PENDING_VERIFICATION' || s == 'PENDING';
                  }).length} pending)',
                ),
                selected: _activeTabIndex == 1,
                onSelected: (_) => setState(() => _activeTabIndex = 1),
              ),
            ],
          ),
          const SizedBox(height: 16),

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

                final monthYearFilter = MonthYearSelector(
                  selectedMonth: _selectedMonthNumber,
                  selectedYear: _selectedYearNumber,
                  onChanged: (m, y) {
                    setState(() {
                      _selectedMonthNumber = m;
                      _selectedYearNumber = y;
                      const mNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
                      _selectedMonth = '${mNames[m - 1]} $y';
                    });
                  },
                );

                final statusDropdown = AppDropdown.simple(
                  height: 40,
                  value: _selectedStatus,
                  items: const ['All Payment Statuses', 'Paid', 'Pending', 'Partial', 'Overdue'],
                  onChanged: (v) => setState(() => _selectedStatus = v),
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
                          SizedBox(width: 175, child: statusDropdown),
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
                    SizedBox(width: 175, child: statusDropdown),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. Invoice Table or UPI Reconciliation Queue
          Builder(
            builder: (context) {
              if (_activeTabIndex == 1) {
                final upiBox = _buildUpiReconciliationBox(context);
                return isCompact
                    ? SizedBox(height: 400, child: upiBox)
                    : Expanded(child: upiBox);
              }
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
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PremiumDialog(
              maxWidth: 460,
              title: 'Record Payment',
              subtitle: invoice['name']?.toString() ?? 'Resident',
              icon: Icons.payments_rounded,
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting ? null : () async {
                    final enteredAmount = int.tryParse(amountController.text) ?? (invoice['expected'] ?? 8000);
                    final invId = invoice['id']?.toString();
                    setDialogState(() => isSubmitting = true);
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
                        setDialogState(() => isSubmitting = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to record payment: $e'), backgroundColor: AppTheme.statusRed),
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
                        SnackBar(content: Text('Payment of ₹ $enteredAmount collected for ${invoice['name']}!'), backgroundColor: AppTheme.statusOk),
                      );
                    }
                  },
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(isSubmitting ? 'Recording...' : 'Confirm Payment'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Property: ${invoice['property'] ?? 'Green View PG - Hebbal'}', style: const TextStyle(color: AppTheme.textGrey, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Room: ${invoice['room'] ?? '101'} • Month: ${invoice['month'] ?? '2026-09'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textDark)),
                            Text('Due: ₹${invoice['expected'] ?? 8000}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.statusRed)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PremiumFormField(
                    label: 'Collect Amount (₹)',
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.currency_rupee_rounded,
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  const Text('Payment Mode', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5)),
                    ),
                    items: ['UPI', 'Cash', 'Bank Transfer'].map((String method) {
                      return DropdownMenuItem(value: method, child: Text(method, style: const TextStyle(fontSize: 13)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedMethod = val);
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

  Widget _buildUpiReconciliationBox(BuildContext context) {
    final txs = _filteredTransactions;
    return Container(
      decoration: modernTableDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const [
                ('ALL', 'All Transactions'),
                ('PENDING', 'Pending Verification'),
                ('VERIFIED', 'Verified'),
                ('FAILED', 'Failed / Cancelled'),
              ])
                ChoiceChip(
                  label: Text(entry.$2, style: const TextStyle(fontSize: 12)),
                  selected: _upiStatusFilter == entry.$1,
                  onSelected: (_) => setState(() => _upiStatusFilter = entry.$1),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: txs.isEmpty
                ? const EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'No UPI transactions',
                    subtitle: 'Direct UPI payment attempts and verified receipts will appear here.',
                  )
                : ListView.separated(
                    itemCount: txs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final tx = txs[i];
                      final status = (tx['status'] ?? '').toString().toUpperCase();
                      final isVerified = status == 'PAID' || status == 'SUCCESS';
                      final isPending = status == 'PENDING_VERIFICATION' || status == 'PENDING';
                      final txnRef = tx['transaction_ref']?.toString() ?? '-';
                      final utr = tx['bank_reference']?.toString() ??
                          tx['client_upi_txn_id']?.toString() ??
                          '-';
                      final reconStatus = tx['reconciliation_status']?.toString() ?? status;
                      final timestamp = (tx['paid_at'] ?? tx['created_at'] ?? '').toString();
                      final badgeCol = isVerified
                          ? const Color(0xFF059669)
                          : (isPending ? const Color(0xFFD97706) : const Color(0xFFDC2626));

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${tx['resident_name'] ?? 'Resident'} · ${tx['invoice_number'] ?? '-'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Txn Ref: $txnRef · UPI/UTR: $utr',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mode: ${tx['payment_mode'] ?? 'UPI'} · $timestamp',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹ ${_formatCurrency((tx['amount'] as num?) ?? 0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: badgeCol.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    reconStatus,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: badgeCol,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            if (isPending)
                              Wrap(
                                spacing: 6,
                                children: [
                                  ElevatedButton(
                                    onPressed: () => _showReconcileUpiDialog(context, tx),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                    child: const Text('Verify', style: TextStyle(fontSize: 12)),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _showReconcileUpiDialog(context, tx, defaultReject: true),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFDC2626),
                                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                    child: const Text('Reject', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              )
                            else if (isVerified && tx['receipt_number'] != null)
                              Text(
                                tx['receipt_number'].toString(),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF059669),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showReconcileUpiDialog(
    BuildContext context,
    Map<String, dynamic> tx, {
    bool defaultReject = false,
  }) {
    final paymentId = (tx['payment_id'] ?? tx['id'] ?? '').toString();
    final utrController = TextEditingController(
      text: tx['client_upi_txn_id']?.toString() ?? '',
    );
    final notesController = TextEditingController();
    String action = defaultReject ? 'REJECT' : 'APPROVE';
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PremiumDialog(
          maxWidth: 480,
          title: action == 'APPROVE' ? 'Verify UPI Credit' : 'Reject Pending UPI',
          subtitle: 'Reconciliation Queue',
          icon: action == 'APPROVE' ? Icons.verified_user_rounded : Icons.highlight_off_rounded,
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton.icon(
              onPressed: isSubmitting ? null : () async {
                final bankRef = utrController.text.trim();
                if (action == 'APPROVE' && bankRef.isEmpty) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a verified Bank UTR / RRN.'),
                      backgroundColor: AppTheme.statusRed,
                    ),
                  );
                  return;
                }
                setDialogState(() => isSubmitting = true);
                try {
                  await AdminApiService.reconcileUpiPayment(
                    paymentId: paymentId,
                    action: action,
                    bankReference: action == 'APPROVE' ? bankRef : null,
                    notes: notesController.text.trim(),
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  _loadInvoicesFromApi();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          action == 'APPROVE'
                              ? 'Payment verified & receipt issued!'
                              : 'Pending payment marked as failed.',
                        ),
                        backgroundColor:
                            action == 'APPROVE' ? AppTheme.statusOk : AppTheme.statusAmb,
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(() => isSubmitting = false);
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(content: Text('Reconciliation error: $e'), backgroundColor: AppTheme.statusRed),
                    );
                  }
                }
              },
              icon: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(action == 'APPROVE' ? Icons.check_circle_outline_rounded : Icons.cancel_outlined, size: 18),
              label: Text(isSubmitting ? 'Processing...' : (action == 'APPROVE' ? 'Verify & Settle' : 'Mark Failed')),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    action == 'APPROVE' ? AppTheme.statusOk : AppTheme.statusRed,
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
                        const Text('Resident', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        Text(
                          tx['resident_name']?.toString() ?? 'Resident',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Invoice #', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        Text(
                          tx['invoice_number']?.toString() ?? '-',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Amount', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        Text(
                          '₹${_formatCurrency((tx['amount'] as num?) ?? 0)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.statusOk),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Txn Ref', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        Text(
                          tx['transaction_ref']?.toString() ?? '-',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textGrey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (action == 'APPROVE') ...[
                PremiumFormField(
                  controller: utrController,
                  label: 'Verified Bank UTR / RRN',
                  hintText: 'Enter 12-digit UTR from bank statement',
                  prefixIcon: Icons.tag_rounded,
                  isRequired: true,
                ),
                const SizedBox(height: 14),
              ],
              PremiumFormField(
                controller: notesController,
                label: action == 'APPROVE' ? 'Reconciliation Notes' : 'Rejection Reason',
                hintText: action == 'APPROVE' ? 'Optional bank reference or comment' : 'Reason for marking failed',
                prefixIcon: Icons.notes_rounded,
                isRequired: action != 'APPROVE',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
