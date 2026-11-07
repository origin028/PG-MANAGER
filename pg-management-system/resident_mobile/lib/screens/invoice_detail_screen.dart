import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/invoice.dart';
import '../providers/invoice_provider.dart';
import '../providers/payment_provider.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/status_chip.dart';
import 'payment_status_screen.dart';
import 'receipt_detail_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final String invoiceId;

  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInvoice();
    });
  }

  void _loadInvoice() {
    Provider.of<InvoiceProvider>(context, listen: false).fetchInvoiceDetail(widget.invoiceId);
  }

  void _startPayment(ResidentInvoiceDetail invoice) async {
    final paymentProv = Provider.of<PaymentProvider>(context, listen: false);

    // 1. Call backend to initiate order
    final paymentRequest = await paymentProv.initiatePayment(
      invoiceId: invoice.id,
      amount: invoice.remainingAmount,
    );

    if (paymentRequest == null) {
      if (mounted && paymentProv.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(paymentProv.errorMessage!),
            backgroundColor: AppTheme.statusOverdue,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // 2. Open Razorpay Checkout modal
    paymentProv.openRazorpayCheckout(
      paymentRequest: paymentRequest,
      onComplete: (status) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PaymentStatusScreen(
              paymentStatus: status,
              invoiceId: invoice.id,
            ),
          ),
        );
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppTheme.statusOverdue,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoiceProv = Provider.of<InvoiceProvider>(context);
    final paymentProv = Provider.of<PaymentProvider>(context);
    final invoice = invoiceProv.selectedInvoice;

    if (invoiceProv.isLoading && invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice Details')),
        body: const Center(child: AppLoadingIndicator(message: 'Loading invoice...')),
      );
    }

    if (invoiceProv.errorMessage != null && invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice Details')),
        body: ErrorStateWidget(
          message: invoiceProv.errorMessage!,
          onRetry: _loadInvoice,
        ),
      );
    }

    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice Details')),
        body: const Center(child: Text('Invoice not found.')),
      );
    }

    final bool isDue = invoice.remainingAmount > 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(invoice.invoiceNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvoice,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header summary card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invoice.propertyName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Invoice ${invoice.invoiceNumber}',
                                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        StatusChip(status: invoice.status),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Billing Period', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(invoice.billingMonth, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Due Date', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(invoice.dueDate, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Financial breakdown card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Summary',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildRow('Rent / Invoice Amount', currencyFormat.format(invoice.amount)),
                    const SizedBox(height: 10),
                    _buildRow('Amount Paid', currencyFormat.format(invoice.paidAmount), color: AppTheme.statusPaid),
                    const Divider(height: 24),
                    _buildRow(
                      'Remaining Balance Due',
                      currencyFormat.format(invoice.remainingAmount),
                      isTotal: true,
                      color: isDue ? AppTheme.statusOverdue : AppTheme.statusPaid,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Metadata card (Notes or Settlement details)
            if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(invoice.notes!, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            if (isDue) ...[
              ElevatedButton.icon(
                onPressed: paymentProv.flowState == PaymentFlowState.initiating
                    ? null
                    : () => _startPayment(invoice),
                icon: paymentProv.flowState == PaymentFlowState.initiating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.payment_rounded),
                label: Text(
                  paymentProv.flowState == PaymentFlowState.initiating
                      ? 'Preparing Payment...'
                      : 'Pay ${currencyFormat.format(invoice.remainingAmount)} with Razorpay',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Razorpay Test Mode • UPI / Cards / NetBanking Supported',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
            ] else if (invoice.receiptId != null) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReceiptDetailScreen(receiptId: invoice.receiptId!),
                    ),
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('View Official Digital Receipt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String title, String value, {bool isTotal = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isTotal ? 15 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
            color: color ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
