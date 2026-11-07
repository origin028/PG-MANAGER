import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/invoice.dart';
import '../providers/invoice_provider.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/status_chip.dart';
import 'invoice_detail_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InvoiceProvider>(context, listen: false).fetchInvoices();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Provider.of<InvoiceProvider>(context, listen: false).fetchInvoices();
  }

  List<ResidentInvoiceItem> _filterInvoices(List<ResidentInvoiceItem> all, int tabIndex) {
    switch (tabIndex) {
      case 1: // Pending / Due
        return all.where((inv) => inv.isPending || inv.isPartiallyPaid || inv.isOverdue).toList();
      case 2: // Paid
        return all.where((inv) => inv.isPaid).toList();
      default: // All
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoiceProv = Provider.of<InvoiceProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Invoices'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Due / Pending'),
            Tab(text: 'Settled'),
          ],
        ),
      ),
      body: invoiceProv.isLoading && invoiceProv.invoices.isEmpty
          ? const Center(child: AppLoadingIndicator(message: 'Loading your invoices...'))
          : invoiceProv.errorMessage != null && invoiceProv.invoices.isEmpty
              ? ErrorStateWidget(message: invoiceProv.errorMessage!, onRetry: _refresh)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInvoiceList(_filterInvoices(invoiceProv.invoices, 0)),
                    _buildInvoiceList(_filterInvoices(invoiceProv.invoices, 1)),
                    _buildInvoiceList(_filterInvoices(invoiceProv.invoices, 2)),
                  ],
                ),
    );
  }

  Widget _buildInvoiceList(List<ResidentInvoiceItem> list) {
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            EmptyStateWidget(
              title: 'No invoices in this tab',
              message: 'Invoices matching this filter will appear here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final invoice = list[idx];
          return Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        StatusChip(status: invoice.status),
                      ],
                    ),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Billing Month',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              invoice.billingMonth,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currencyFormat.format(invoice.amount),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Due Date: ${invoice.dueDate}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (invoice.remainingAmount > 0)
                          Text(
                            'Due: ${currencyFormat.format(invoice.remainingAmount)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.statusOverdue,
                            ),
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
    );
  }
}
