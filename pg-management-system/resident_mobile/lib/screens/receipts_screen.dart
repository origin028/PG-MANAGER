import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/receipt_provider.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/loading_indicator.dart';
import 'receipt_detail_screen.dart';

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ReceiptProvider>(context, listen: false).fetchReceipts();
    });
  }

  Future<void> _refresh() async {
    await Provider.of<ReceiptProvider>(context, listen: false).fetchReceipts();
  }

  @override
  Widget build(BuildContext context) {
    final receiptProv = Provider.of<ReceiptProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Digital Receipts'),
      ),
      body: receiptProv.isLoading && receiptProv.receipts.isEmpty
          ? const Center(child: AppLoadingIndicator(message: 'Loading receipts...'))
          : receiptProv.errorMessage != null && receiptProv.receipts.isEmpty
              ? ErrorStateWidget(message: receiptProv.errorMessage!, onRetry: _refresh)
              : receiptProv.receipts.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: Icons.receipt_long_outlined,
                            title: 'No receipts yet',
                            message: 'When you pay your rent invoices, verified digital receipts will be generated here automatically.',
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: receiptProv.receipts.length,
                        separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final receipt = receiptProv.receipts[idx];
                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ReceiptDetailScreen(receiptId: receipt.id),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.secondary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.verified_outlined,
                                        color: AppTheme.secondary,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            receipt.receiptNumber,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'For ${receipt.billingMonth} • ${receipt.paymentMode}',
                                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Issued: ${receipt.issuedAt}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          currencyFormat.format(receipt.amount),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppTheme.statusPaid,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Row(
                                          children: [
                                            Text(
                                              'View',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.primaryLight,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 16,
                                              color: AppTheme.primaryLight,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
