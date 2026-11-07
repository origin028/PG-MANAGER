import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late final List<Map<String, dynamic>> _invoices;

  @override
  void initState() {
    super.initState();
    final rent = AppData.currentResident['rent'] ?? 8000;
    final isRentPaid = AppData.currentResident['rent_status']?.toString().toLowerCase() == 'paid';
    _invoices = [
      {'id': 'INV-2026-010', 'month': 'November 2026', 'amount': (rent is num ? rent.toDouble() : 8000.0), 'status': isRentPaid ? 'Paid' : 'Pending', 'date': '05 Nov 2026', 'invoice_type': 'RENT'},
      {'id': 'INV-2026-009', 'month': 'October 2026', 'amount': 8000.0, 'status': 'Paid', 'date': '05 Oct 2026', 'invoice_type': 'RENT'},
      {'id': 'INV-2026-008', 'month': 'September 2026', 'amount': 8000.0, 'status': 'Paid', 'date': '05 Sep 2026', 'invoice_type': 'RENT'},
    ];
    _loadInvoicesFromApi();
  }

  void _loadInvoicesFromApi() async {
    try {
      final invs = await ResidentApiService.getInvoices();
      if (invs.isNotEmpty && mounted) {
        setState(() {
          _invoices.clear();
          for (var inv in invs) {
            final amt = inv['balance_amount'] ?? inv['amount'] ?? 0;
            final double numAmount = amt is num ? amt.toDouble() : (double.tryParse(amt.toString()) ?? 0.0);
            _invoices.add({
              'id': inv['id']?.toString() ?? '',
              'invoice_number': inv['invoice_number']?.toString() ?? '',
              'invoice_type': inv['invoice_type']?.toString() ?? 'RENT',
              'notes': inv['notes']?.toString() ?? '',
              'month': inv['billing_month'] != null
                  ? 'Month ${inv['billing_month']}'
                  : (inv['due_date'] != null ? 'Month ${inv['due_date'].toString().substring(0, 7)}' : 'Current Month'),
              'amount': numAmount,
              'status': inv['status'] == 'PAID' ? 'Paid' : (inv['status'] == 'PARTIAL' ? 'Partial' : 'Pending'),
              'date': inv['due_date']?.toString() ?? '05 Nov 2026',
            });
          }
        });
      }
    } catch (e) {
      debugPrint('API resident getInvoices error: $e');
    }
  }

  String _formatAmount(dynamic amt) {
    if (amt == null) return '0.00';
    final num val = amt is num ? amt : (num.tryParse(amt.toString()) ?? 0);
    if (val % 1 == 0 && val >= 100) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(2);
  }

  void _openRentPayment(BuildContext context, Map<String, dynamic> invoice) {
    context.push('/rent-payment', extra: {...invoice, 'autoOpen': true}).then((_) {
      _loadInvoicesFromApi();
      setState(() {
        final isRentPaid = AppData.currentResident['rent_status']?.toString().toLowerCase() == 'paid';
        if (isRentPaid && _invoices.isNotEmpty) {
          final idx = _invoices.indexWhere((i) => i['id'] == invoice['id']);
          if (idx != -1) {
            _invoices[idx]['status'] = 'Paid';
          }
        }
      });
    });
  }

  void _openReceipt(BuildContext context, Map<String, dynamic> invoice) {
    context.push(
      '/receipt',
      extra: {
        'invoiceId': (invoice['invoice_number'] != null && invoice['invoice_number'].toString().isNotEmpty)
            ? invoice['invoice_number']
            : invoice['id'],
        'amount': invoice['amount'],
        'month': invoice['month'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingInvoice = _invoices.firstWhere(
      (inv) => inv['status'] == 'Pending' || inv['status'] == 'Partial',
      orElse: () => _invoices.isNotEmpty ? _invoices.first : {'amount': 0.0, 'status': 'Paid', 'date': '-'},
    );
    final isPending = pendingInvoice['status'] == 'Pending' || pendingInvoice['status'] == 'Partial';

    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final borderCol = AppTheme.borderCol(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final pageBg = AppTheme.pageBg(context);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text('Rent & Payments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPri)),
        backgroundColor: cardBg,
        iconTheme: IconThemeData(color: textPri),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 22.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Cycle Rent Card with Theme Shaded Background & High-Contrast Typography
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? const LinearGradient(
                              colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : AppTheme.heroCardGradient,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? const Color(0xFF4338CA) : const Color(0xFFE0E7FF), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x144F46E5),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'MONTHLY RENT',
                              style: TextStyle(
                                color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Icon(Icons.account_balance_wallet_rounded, color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5), size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isPending ? '₹ ${_formatAmount(pendingInvoice['amount'])}' : '₹ 0',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPending ? 'Due on ${pendingInvoice['date']}' : 'All dues cleared for this month',
                          style: TextStyle(
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  Text('Payment History & Invoices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPri)),
                  const SizedBox(height: 16),

                  ..._invoices.map((invoice) {
                    final isPaid = invoice['status'] == 'Paid';
                    final isTest = (invoice['invoice_type'] ?? '').toString().startsWith('TEST');

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isPaid ? borderCol : const Color(0x4D4F46E5),
                          width: isPaid ? 1.0 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? const Color(0x1A000000) : const Color(0x05000000),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            invoice['month'] ?? 'Current Month',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textPri),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isTest) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF3B82F6), width: 0.8),
                                            ),
                                            child: const Text(
                                              'TEST',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF3B82F6),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      invoice['invoice_number'] != null && invoice['invoice_number'].toString().isNotEmpty
                                          ? '${invoice['invoice_number']} • Due: ${invoice['date']}'
                                          : 'Invoice Date: ${invoice['date']}',
                                      style: TextStyle(color: textSec, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (invoice['notes'] != null && invoice['notes'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        invoice['notes'].toString(),
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('₹ ${_formatAmount(invoice['amount'])}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPri)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Divider(height: 1, color: borderCol),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPaid
                                      ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                                      : (isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  invoice['status'],
                                  style: TextStyle(
                                    color: isPaid
                                        ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF059669))
                                        : (isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309)),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (isPaid)
                                TextButton.icon(
                                  onPressed: () => _openReceipt(context, invoice),
                                  icon: const Icon(Icons.receipt_long_rounded, size: 16, color: AppTheme.primaryBlue),
                                  label: const Text('Receipt', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                                )
                              else
                                ElevatedButton(
                                  onPressed: () => _openRentPayment(context, invoice),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    minimumSize: const Size(0, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: const Text('Pay Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
