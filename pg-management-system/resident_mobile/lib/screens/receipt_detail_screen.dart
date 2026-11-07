import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/receipt_provider.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/loading_indicator.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final String receiptId;

  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReceipt();
    });
  }

  void _loadReceipt() {
    Provider.of<ReceiptProvider>(context, listen: false).fetchReceiptDetail(widget.receiptId);
  }

  @override
  Widget build(BuildContext context) {
    final receiptProv = Provider.of<ReceiptProvider>(context);
    final receipt = receiptProv.selectedReceipt;

    if (receiptProv.isLoading && receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Digital Receipt')),
        body: const Center(child: AppLoadingIndicator(message: 'Generating official receipt...')),
      );
    }

    if (receiptProv.errorMessage != null && receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Digital Receipt')),
        body: ErrorStateWidget(message: receiptProv.errorMessage!, onRetry: _loadReceipt),
      );
    }

    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Digital Receipt')),
        body: const Center(child: Text('Receipt not found.')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Official Receipt'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Receipt Canvas / Paper Container
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Receipt Top Banner
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'PAYMENT RECEIPT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          receipt.propertyName,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  // Amount Callout
                  Container(
                    padding: const EdgeInsets.all(20),
                    color: AppTheme.statusPaid.withValues(alpha: 0.08),
                    child: Column(
                      children: [
                        const Text(
                          'AMOUNT PAID',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          currencyFormat.format(receipt.amount),
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.statusPaid,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.statusPaid.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'SETTLED & CONFIRMED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.statusPaid,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Receipt Meta
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('TRANSACTION DETAILS'),
                        const SizedBox(height: 12),
                        _buildReceiptRow('Receipt Number', receipt.receiptNumber),
                        _buildReceiptRow('Date & Time', receipt.issuedAt),
                        _buildReceiptRow('Invoice Number', receipt.invoiceNumber),
                        _buildReceiptRow('Billing Month', receipt.billingMonth),
                        _buildReceiptRow('Payment Mode', receipt.paymentMode),
                        if (receipt.gatewayPaymentId != null)
                          _buildReceiptRow('Gateway Ref ID', receipt.gatewayPaymentId!),

                        const Divider(height: 32, color: Color(0xFFF1F5F9)),

                        _buildSectionHeader('RESIDENT & STAY DETAILS'),
                        const SizedBox(height: 12),
                        _buildReceiptRow('Resident Name', receipt.residentName),
                        _buildReceiptRow('Phone Number', receipt.residentPhone),
                        if (receipt.residentEmail != null && receipt.residentEmail!.isNotEmpty)
                          _buildReceiptRow('Email', receipt.residentEmail!),
                        if (receipt.roomNumber != null)
                          _buildReceiptRow('Room / Bed', 'Room ${receipt.roomNumber}, Bed ${receipt.bedNumber ?? "-"}'),
                        if (receipt.propertyAddress != null)
                          _buildReceiptRow('PG Address', receipt.propertyAddress!),

                        const Divider(height: 32, color: Color(0xFFF1F5F9)),

                        // Digital Signature / Verified Stamp
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_outlined, color: AppTheme.secondary, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tamper-evident Digital Receipt',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Issued directly by Origin PG Management backend upon verified payment settlement.',
                                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppTheme.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
