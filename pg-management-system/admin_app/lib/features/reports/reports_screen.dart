import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/data/app_data.dart';
import '../../core/services/admin_api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  double _grossCollections = 156800.0;
  double _operationalExpenses = 45000.0;

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_loadReportFromApi);
    _loadReportFromApi();
  }

  void _loadReportFromApi() async {
    final propId = AppData.selectedPropertyId;
    try {
      final data = await AdminApiService.getFinancialReport(propertyId: propId);
      if (data.isNotEmpty && mounted) {
        setState(() {
          _grossCollections = (data['gross_collections'] ?? 156800.0).toDouble();
          _operationalExpenses = (data['total_expenses'] ?? 45000.0).toDouble();
        });
      }
    } catch (e) {
      debugPrint('API getFinancialReport error: $e');
    }
  }

  String _paymentMonth = 'September 2026';
  String _paymentProperty = 'All Properties';

  String _occupancyMonth = 'September 2026';
  String _occupancyProperty = 'All Properties';

  final List<String> _months = [
    'September 2026',
    'August 2026',
    'July 2026',
    'June 2026',
    'All of 2026',
  ];

  final List<String> _properties = [
    'All Properties',
    'Green View PG - Hebbal',
    'BNR Luxury PG',
    'Skyline Girls PG',
    'Green Nest PG',
  ];

  @override
  Widget build(BuildContext context) {
    final grossCollections = _grossCollections.toInt();
    final operationalExpenses = _operationalExpenses.toInt();
    final netProfit = grossCollections - operationalExpenses;
    final profitMargin = grossCollections > 0 ? ((netProfit / grossCollections) * 100).toStringAsFixed(1) : '0.0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text('Reports & Analytics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 20),

          // 1. Top Banner: Executive Performance & Profitability
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.query_stats, color: AppTheme.primaryBlue, size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Executive Performance & Profitability',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Text(
                        'FY 2026-27',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Large numbers: GROSS COLLECTIONS - OPERATIONAL EXPENSES = NET OPERATING PROFIT
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 750;

                    final grossItem = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GROSS COLLECTIONS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textGrey, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '₹ 1,56,800',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 2),
                        const Text('98% of total billed', style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
                      ],
                    );

                    final minusSign = Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.remove, size: 20, color: AppTheme.textGrey),
                    );

                    final expensesItem = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OPERATIONAL EXPENSES',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textGrey, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '₹ 45,000',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(height: 2),
                        const Text('Utilities & payroll included', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                      ],
                    );

                    final equalsSign = Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
                    );

                    final profitItem = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NET OPERATING PROFIT',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textGrey, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '₹ 1,11,800',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Text(
                            'Profit Margin: $profitMargin%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          grossItem,
                          const SizedBox(height: 12),
                          Row(children: [minusSign, const SizedBox(width: 10), const Flexible(child: Text('Minus Operational Costs', style: TextStyle(fontSize: 12, color: AppTheme.textGrey), overflow: TextOverflow.ellipsis))]),
                          const SizedBox(height: 12),
                          expensesItem,
                          const SizedBox(height: 12),
                          Row(children: [equalsSign, const SizedBox(width: 10), const Flexible(child: Text('Equals Net Profit', style: TextStyle(fontSize: 12, color: AppTheme.textGrey), overflow: TextOverflow.ellipsis))]),
                          const SizedBox(height: 12),
                          profitItem,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: grossItem),
                        minusSign,
                        const SizedBox(width: 16),
                        Expanded(child: expensesItem),
                        const SizedBox(width: 16),
                        equalsSign,
                        const SizedBox(width: 16),
                        Expanded(child: profitItem),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 2. Downloads Section
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statement Downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              SizedBox(height: 2),
              Text('Generate auditable Excel spreadsheets filtered by billing cycle and property', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
            ],
          ),
          const SizedBox(height: 14),

          // Side-by-side Cards: 'Payment Statement' and 'Occupancy & Resident Statement'
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 750;

              final paymentStatementCard = _buildStatementCard(
                context: context,
                title: 'Payment Statement',
                subtitle: 'Full itemized register of rents, dues, pending collections, modes of payment, and transaction ref IDs.',
                icon: Icons.receipt_long_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
                selectedMonth: _paymentMonth,
                selectedProperty: _paymentProperty,
                onMonthChanged: (val) => setState(() => _paymentMonth = val),
                onPropertyChanged: (val) => setState(() => _paymentProperty = val),
                onDownload: () async {
                  final propId = AppData.selectedPropertyId;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Exporting Payment Statement for $_paymentMonth ($_paymentProperty)...'),
                      backgroundColor: AppTheme.primaryBlue,
                    ),
                  );
                  try {
                    final bytes = await AdminApiService.exportPaymentsReportCsv(propertyId: propId);
                    if (context.mounted && bytes.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Payment Statement CSV generated (${bytes.length} bytes)!'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('API exportPaymentsReportCsv error: $e');
                  }
                },
              );

              final occupancyStatementCard = _buildStatementCard(
                context: context,
                title: 'Occupancy & Resident Statement',
                subtitle: 'Comprehensive audit list of all onboarded residents, room & bed allocations, security deposits, and KYC verification statuses.',
                icon: Icons.people_alt_outlined,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
                selectedMonth: _occupancyMonth,
                selectedProperty: _occupancyProperty,
                onMonthChanged: (val) => setState(() => _occupancyMonth = val),
                onPropertyChanged: (val) => setState(() => _occupancyProperty = val),
                onDownload: () async {
                  final propId = AppData.selectedPropertyId ?? (AppData.properties.isNotEmpty ? AppData.properties.first['id']?.toString() : null);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Exporting Occupancy Statement for $_occupancyMonth ($_occupancyProperty)...'),
                      backgroundColor: const Color(0xFF059669),
                    ),
                  );
                  if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                    try {
                      final bytes = await AdminApiService.exportOccupancyReportCsv(propId);
                      if (context.mounted && bytes.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Occupancy Statement CSV generated (${bytes.length} bytes)!'),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('API exportOccupancyReportCsv error: $e');
                    }
                  }
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    paymentStatementCard,
                    const SizedBox(height: 16),
                    occupancyStatementCard,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: paymentStatementCard),
                  const SizedBox(width: 16),
                  Expanded(child: occupancyStatementCard),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatementCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String selectedMonth,
    required String selectedProperty,
    required ValueChanged<String> onMonthChanged,
    required ValueChanged<String> onPropertyChanged,
    required VoidCallback onDownload,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
          ),
          const SizedBox(height: 18),

          // Dropdowns: Month/Year & Property
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Billing Period', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
                    const SizedBox(height: 6),
                    AppDropdown.simple(
                      height: 38,
                      value: selectedMonth,
                      items: _months,
                      onChanged: onMonthChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Property', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
                    const SizedBox(height: 6),
                    AppDropdown.simple(
                      height: 38,
                      value: selectedProperty,
                      items: _properties,
                      onChanged: onPropertyChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Download Excel button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download, size: 18),
              label: const Text(
                'Download Excel',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
