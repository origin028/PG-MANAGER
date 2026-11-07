import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/payment.dart';
import '../providers/invoice_provider.dart';
import '../providers/payment_provider.dart';
import '../providers/receipt_provider.dart';
import '../widgets/status_chip.dart';
import 'invoice_detail_screen.dart';
import 'receipt_detail_screen.dart';

class PaymentStatusScreen extends StatefulWidget {
  final PaymentStatus paymentStatus;
  final String invoiceId;

  const PaymentStatusScreen({
    super.key,
    required this.paymentStatus,
    required this.invoiceId,
  });

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  late PaymentStatus _currentStatus;
  bool _isChecking = false;
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.paymentStatus;

    // Refresh invoices and receipts caches in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InvoiceProvider>(context, listen: false).fetchInvoices();
      Provider.of<ReceiptProvider>(context, listen: false).fetchReceipts();
    });
  }

  void _checkStatusAgain() async {
    setState(() => _isChecking = true);
    final paymentProv = Provider.of<PaymentProvider>(context, listen: false);
    final updated = await paymentProv.checkPaymentStatus(_currentStatus.paymentId);
    if (mounted) {
      setState(() {
        if (updated != null) _currentStatus = updated;
        _isChecking = false;
      });
      if (_currentStatus.isSuccess) {
        Provider.of<InvoiceProvider>(context, listen: false).fetchInvoices();
        Provider.of<ReceiptProvider>(context, listen: false).fetchReceipts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = _currentStatus.isSuccess;
    final isFailed = _currentStatus.isFailed;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Payment Status'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: (isSuccess
                              ? AppTheme.statusPaid
                              : (isFailed ? AppTheme.statusOverdue : AppTheme.statusPending))
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSuccess
                          ? Icons.check_circle_rounded
                          : (isFailed ? Icons.cancel_rounded : Icons.hourglass_top_rounded),
                      size: 64,
                      color: isSuccess
                          ? AppTheme.statusPaid
                          : (isFailed ? AppTheme.statusOverdue : AppTheme.statusPending),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isSuccess
                      ? 'Payment Successful!'
                      : (isFailed ? 'Payment Failed' : 'Payment Processing'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isSuccess
                      ? 'Your payment has been cryptographically verified and settled.'
                      : (isFailed
                          ? 'The transaction could not be completed or was cancelled.'
                          : 'Awaiting webhook settlement confirmation from Razorpay.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 32),

                // Transaction Details Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        _buildDetailRow('Amount Paid', currencyFormat.format(_currentStatus.amount)),
                        const Divider(height: 20),
                        _buildDetailRow('Payment Number', _currentStatus.paymentNumber),
                        const Divider(height: 20),
                        _buildDetailRow('Payment Mode', _currentStatus.paymentMode),
                        const Divider(height: 20),
                        _buildDetailRow('Status', '', customValue: StatusChip(status: _currentStatus.status)),
                        if (_currentStatus.gatewayPaymentId != null) ...[
                          const Divider(height: 20),
                          _buildDetailRow('Razorpay Payment ID', _currentStatus.gatewayPaymentId!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Contextual Action Buttons
                if (isSuccess && _currentStatus.receiptId != null) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailScreen(receiptId: _currentStatus.receiptId!),
                        ),
                      );
                    },
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('View Official Digital Receipt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (isFailed) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => InvoiceDetailScreen(invoiceId: widget.invoiceId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (!isSuccess && !isFailed) ...[
                  OutlinedButton.icon(
                    onPressed: _isChecking ? null : _checkStatusAgain,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Check Status Again'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Back to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Widget? customValue}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        customValue ??
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
      ],
    );
  }
}
