import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/data/app_data.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_dialogs.dart';
import '../../core/widgets/table_components.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_loadExpensesFromApi);
    _loadExpensesFromApi();
  }

  void _loadExpensesFromApi() async {
    final propId = AppData.selectedPropertyId;
    try {
      final list = await AdminApiService.getExpenses(propertyId: propId);
      if (list.isNotEmpty && mounted) {
        setState(() {
          AppData.otherExpenses = list.map((e) => <String, dynamic>{
            'id': e['id']?.toString() ?? '',
            'description': e['title'] ?? 'Expense',
            'amount': (e['amount'] ?? 0).toInt(),
            'category': e['category'] ?? 'Utilities',
            'property': e['property_name'] ?? AppData.selectedProperty,
            'date': e['expense_date']?.toString() ?? '2026-10-12',
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('API getExpenses error: $e');
    }
  }
  String _searchQuery = '';

  // Shared Expenses from AppData (persists across navigation)
  List<Map<String, dynamic>> get _otherExpenses => AppData.otherExpenses;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    return _otherExpenses.where((exp) {
      final query = _searchQuery.toLowerCase().trim();
      if (query.isEmpty) return true;
      final desc = (exp['description'] ?? '').toString().toLowerCase();
      final cat = (exp['category'] ?? '').toString().toLowerCase();
      final prop = (exp['property'] ?? '').toString().toLowerCase();
      final date = (exp['date'] ?? '').toString().toLowerCase();
      return desc.contains(query) || cat.contains(query) || prop.contains(query) || date.contains(query);
    }).toList();
  }

  void _showAddExpenseDialog() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Utilities';
    String selectedProperty = AppData.selectedProperty;
    bool isSubmitting = false;

    showPremiumDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dynamicProps = AppData.propertyNames.isNotEmpty ? AppData.propertyNames : [selectedProperty];
            if (!dynamicProps.contains(selectedProperty)) {
              selectedProperty = dynamicProps.first;
            }

            return PremiumDialog(
              maxWidth: 480,
              icon: Icons.receipt_long_rounded,
              title: 'Add New Expense',
              subtitle: 'Record an operational expenditure or utility payment',
              actions: [
                OutlinedButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText,
                    side: BorderSide(color: isDark ? AppTheme.borderColorDark : AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final desc = titleController.text.trim();
                          final amt = int.tryParse(amountController.text.trim()) ?? 0;
                          if (desc.isEmpty || amt <= 0) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter valid description and amount'), backgroundColor: AppTheme.statusRed),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          // Find matching property ID
                          String? targetPropId;
                          for (var p in AppData.properties) {
                            if (p['name'] == selectedProperty) {
                              targetPropId = p['id']?.toString();
                              break;
                            }
                          }
                          targetPropId ??= AppData.selectedPropertyId;

                          String? createdExpenseId;
                          if (targetPropId != null && targetPropId.isNotEmpty && !targetPropId.startsWith('p')) {
                            try {
                              String backendCategory = 'OTHER';
                              final catUpper = selectedCategory.toUpperCase();
                              if (catUpper.contains('UTIL')) {
                                backendCategory = 'UTILITIES';
                              } else if (catUpper.contains('MAINT')) {
                                backendCategory = 'MAINTENANCE';
                              } else if (catUpper.contains('INTERNET')) {
                                backendCategory = 'INTERNET';
                              } else if (catUpper.contains('FOOD')) {
                                backendCategory = 'GROCERIES';
                              } else if (catUpper.contains('SALARY')) {
                                backendCategory = 'SALARY';
                              }

                              final created = await AdminApiService.createExpense({
                                'property_id': targetPropId,
                                'title': desc,
                                'amount': amt.toDouble(),
                                'category': backendCategory,
                                'method': 'UPI',
                                'date': DateTime.now().toIso8601String().substring(0, 10),
                              });
                              if (created.isNotEmpty && created['id'] != null) {
                                createdExpenseId = created['id'].toString();
                              }
                              _loadExpensesFromApi();
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('Failed to log expense: $e'), backgroundColor: AppTheme.statusRed),
                                );
                              }
                              return;
                            }
                          }

                          final newExpense = <String, dynamic>{
                            'date': 'Today',
                            'category': selectedCategory,
                            'description': desc,
                            'amount': amt,
                            'property': selectedProperty,
                          };
                          if (createdExpenseId != null) {
                            newExpense['id'] = createdExpenseId;
                          }

                          if (!mounted) return;
                          setState(() {
                            _otherExpenses.insert(0, newExpense);
                          });

                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Expense logged successfully!'), backgroundColor: AppTheme.successGreen),
                          );
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(isSubmitting ? 'Saving...' : 'Save Expense', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PremiumFormField(
                    label: 'Description / Purpose',
                    isRequired: true,
                    controller: titleController,
                    hintText: 'e.g. Lift maintenance, Electricity bill',
                    prefixIcon: const Icon(Icons.edit_note_rounded, size: 18),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PremiumFormField(
                          label: 'Amount (₹)',
                          isRequired: true,
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          hintText: 'e.g. 3500',
                          prefixText: '₹ ',
                          prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Category',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: selectedCategory,
                              isExpanded: true,
                              decoration: AppTheme.formDropdownDecoration(
                                fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                              ),
                              dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                              icon: Icon(Icons.keyboard_arrow_down, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText),
                              items: ['Utilities', 'Maintenance', 'Internet', 'Food & Supplies', 'Other'].map((String cat) {
                                return DropdownMenuItem(value: cat, child: Text(cat, overflow: TextOverflow.ellipsis));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setDialogState(() => selectedCategory = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Property',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.primaryTextDark : AppTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedProperty,
                    isExpanded: true,
                    decoration: AppTheme.formDropdownDecoration(
                      fillColor: isDark ? AppTheme.softBackgroundDark : AppTheme.softBackground,
                    ),
                    dropdownColor: isDark ? AppTheme.cardBackgroundDark : AppTheme.cardBackground,
                    icon: Icon(Icons.keyboard_arrow_down, color: isDark ? AppTheme.secondaryTextDark : AppTheme.secondaryText),
                    items: dynamicProps.map((String prop) {
                      return DropdownMenuItem(value: prop, child: Text(prop, overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedProperty = val);
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

  Widget _buildSummaryCard({
    required String title,
    required String amount,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textGrey),
                ),
                const SizedBox(height: 6),
                Text(
                  amount,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalOtherExpenses = _otherExpenses.fold<int>(0, (sum, exp) => sum + (exp['amount'] as int? ?? 0));
    final filteredExpenses = _filteredExpenses;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          const Text(
            'Expenses',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),

          // Top Summary KPI Card
          LayoutBuilder(
            builder: (context, constraints) {
              final card1 = _buildSummaryCard(
                title: 'Total Expenses',
                amount: '₹ $totalOtherExpenses',
                subtitle: '${_otherExpenses.length} operational expenditures recorded',
                icon: Icons.receipt_long_outlined,
                iconColor: const Color(0xFFDC2626),
                iconBgColor: const Color(0xFFFEF2F2),
              );

              return Row(
                children: [
                  Expanded(child: card1),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Action & Search Row: [ Search Expenses ................ ] [ + Add Expense ]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                final searchField = TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search expenses by description, category, property...',
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

                final addExpenseBtn = ElevatedButton.icon(
                  onPressed: _showAddExpenseDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    minimumSize: const Size(130, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: searchField,
                      ),
                      const SizedBox(height: 12),
                      addExpenseBtn,
                    ],
                  );
                }

                return Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: searchField,
                    ),
                    const SizedBox(width: 14),
                    addExpenseBtn,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Expenses Table (DATE, CATEGORY, DESCRIPTION, AMOUNT, PROPERTY, ACTIONS)
          Container(
            decoration: modernTableDecoration,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 64,
                      columnSpacing: 24,
                      horizontalMargin: 20,
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      headingRowHeight: 46,
                      dataRowColor: modernRowColor,
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                      ),
                      columns: [
                        modernTableColumn('DATE'),
                        modernTableColumn('CATEGORY'),
                        modernTableColumn('DESCRIPTION'),
                        modernTableColumn('AMOUNT'),
                        modernTableColumn('PROPERTY'),
                        modernTableColumn('ACTIONS'),
                      ],
                      rows: filteredExpenses.map((exp) {
                        return DataRow(cells: [
                          DataCell(
                            Text(exp['date'] ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, fontWeight: FontWeight.w500)),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                exp['category'] ?? 'General',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              exp['description'] ?? '',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                            ),
                          ),
                          DataCell(
                            Text(
                              '₹ ${exp['amount']}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                            ),
                          ),
                          DataCell(
                            Text(
                              exp['property'] ?? 'Green View PG - Hebbal',
                              style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                            ),
                          ),
                          DataCell(
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textGrey),
                              tooltip: 'Actions',
                              onSelected: (val) {
                                if (val == 'delete') {
                                  final expId = exp['id']?.toString();
                                  if (expId != null && expId.isNotEmpty && !expId.startsWith('exp-')) {
                                    AdminApiService.deleteExpense(expId).then((_) {
                                      _loadExpensesFromApi();
                                    }).catchError((e) {
                                      debugPrint('API deleteExpense error: $e');
                                    });
                                  }
                                  setState(() => _otherExpenses.remove(exp));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Expense deleted'), backgroundColor: Colors.red),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Action: $val for ${exp['description']}')),
                                  );
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit Expense', style: TextStyle(fontSize: 13))),
                                const PopupMenuItem(value: 'receipt', child: Text('View Receipt', style: TextStyle(fontSize: 13))),
                                const PopupMenuDivider(),
                                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(fontSize: 13, color: Colors.red))),
                              ],
                            ),
                          ),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
