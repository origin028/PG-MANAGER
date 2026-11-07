import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
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

  // Shared Expenses & Salaries from AppData (persists across navigation)
  List<Map<String, dynamic>> get _otherExpenses => AppData.otherExpenses;
  List<Map<String, dynamic>> get _employeeSalaries => AppData.employeeSalaries;

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
    String selectedProperty = 'Green View PG - Hebbal';
    String selectedProperty = AppData.selectedProperty;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final dynamicProps = AppData.propertyNames.isNotEmpty ? AppData.propertyNames : [selectedProperty];
            if (!dynamicProps.contains(selectedProperty)) {
              selectedProperty = dynamicProps.first;
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add New Expense'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Description / Purpose *', hintText: 'e.g. Lift maintenance'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹ '),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedCategory,
                            isExpanded: true,
                            decoration: AppTheme.formDropdownDecoration(labelText: 'Category'),
                            borderRadius: BorderRadius.circular(12),
                            elevation: 2,
                            dropdownColor: Colors.white,
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                            items: ['Utilities', 'Maintenance', 'Internet', 'Food & Supplies', 'Other'].map((String cat) {
                              return DropdownMenuItem(value: cat, child: Text(cat, overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedCategory = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedProperty,
                      isExpanded: true,
                      decoration: AppTheme.formDropdownDecoration(labelText: 'Property'),
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                      items: ['Green View PG - Hebbal', 'BNR Luxury PG', 'Skyline Girls PG'].map((String prop) {
                      items: dynamicProps.map((String prop) {
                        return DropdownMenuItem(value: prop, child: Text(prop, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedProperty = val);
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
                  onPressed: () {
                  onPressed: () async {
                    final desc = titleController.text.trim();
                    final amt = int.tryParse(amountController.text.trim()) ?? 0;
                    if (desc.isEmpty || amt <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Please enter valid description and amount'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final propId = AppData.selectedPropertyId;
                    if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
                      AdminApiService.createExpense({
                        'property_id': propId,
                        'title': desc,
                        'amount': amt.toDouble(),
                        'category': selectedCategory.toUpperCase().replaceAll(' & ', '_').replaceAll(' ', '_'),
                        'method': 'UPI',
                        'date': DateTime.now().toIso8601String().substring(0, 10),
                      }).then((_) {
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
                      }).catchError((e) {
                        debugPrint('API createExpense error: $e');
                      });
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to log expense: $e'), backgroundColor: Colors.red),
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
                      _otherExpenses.insert(0, {
                        'date': 'Today',
                        'category': selectedCategory,
                        'description': desc,
                        'amount': amt,
                        'property': selectedProperty,
                      });
                      _otherExpenses.insert(0, newExpense);
                    });

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Expense logged successfully!'), backgroundColor: Colors.green),
                    );
                  },
                  child: const Text('Add Expense'),
                  child: const Text('Save Expense'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddSalaryDialog() {
    final nameController = TextEditingController();
    final roleController = TextEditingController(text: 'Cook');
    final amountController = TextEditingController();
    String selectedMonth = 'September 2026';
    String selectedProperty = 'Green View PG - Hebbal';
    String selectedProperty = AppData.selectedProperty;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final dynamicProps = AppData.propertyNames.isNotEmpty ? AppData.propertyNames : [selectedProperty];
            if (!dynamicProps.contains(selectedProperty)) {
              selectedProperty = dynamicProps.first;
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Record Employee Salary'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Employee Name *', hintText: 'e.g. Ramesh Kumar'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: roleController,
                            decoration: const InputDecoration(labelText: 'Role / Designation', hintText: 'Cook / Security'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Salary Amount (₹) *', prefixText: '₹ '),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedMonth,
                            isExpanded: true,
                            decoration: AppTheme.formDropdownDecoration(labelText: 'Salary Month'),
                            borderRadius: BorderRadius.circular(12),
                            elevation: 2,
                            dropdownColor: Colors.white,
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                            items: ['September 2026', 'August 2026', 'October 2026'].map((String m) {
                            items: ['September 2026', 'August 2026', 'October 2026', 'November 2026'].map((String m) {
                              return DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedMonth = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedProperty,
                            isExpanded: true,
                            decoration: AppTheme.formDropdownDecoration(labelText: 'Property'),
                            borderRadius: BorderRadius.circular(12),
                            elevation: 2,
                            dropdownColor: Colors.white,
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                            items: ['Green View PG - Hebbal', 'BNR Luxury PG'].map((String prop) {
                            items: dynamicProps.map((String prop) {
                              return DropdownMenuItem(value: prop, child: Text(prop, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedProperty = val);
                            },
                          ),
                        ),
                      ],
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
                  onPressed: () {
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final amt = int.tryParse(amountController.text.trim()) ?? 0;
                    if (name.isEmpty || amt <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Please fill valid name and amount'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    // Find matching property ID
                    String? targetPropId;
                    for (var p in AppData.properties) {
                      if (p['name'] == selectedProperty) {
                        targetPropId = p['id']?.toString();
                        break;
                      }
                    }
                    targetPropId ??= AppData.selectedPropertyId;

                    String? createdSalaryId;
                    if (targetPropId != null && targetPropId.isNotEmpty && !targetPropId.startsWith('p')) {
                      try {
                        final created = await AdminApiService.createExpense({
                          'property_id': targetPropId,
                          'title': 'Salary: $name (${roleController.text.trim()}) - $selectedMonth',
                          'amount': amt.toDouble(),
                          'category': 'SALARY',
                          'method': 'BANK_TRANSFER',
                          'date': DateTime.now().toIso8601String().substring(0, 10),
                        });
                        if (created.isNotEmpty && created['id'] != null) {
                          createdSalaryId = created['id'].toString();
                        }
                        _loadExpensesFromApi();
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to record salary: $e'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }
                    }

                    final newSalary = <String, dynamic>{
                      'name': name,
                      'role': roleController.text.trim(),
                      'payment_date': 'Today',
                      'salary_month': selectedMonth,
                      'amount': amt,
                      'property': selectedProperty,
                    };
                    if (createdSalaryId != null) {
                      newSalary['id'] = createdSalaryId;
                    }

                    if (!mounted) return;
                    setState(() {
                      _employeeSalaries.insert(0, {
                        'name': name,
                        'role': roleController.text.trim(),
                        'payment_date': 'Today',
                        'salary_month': selectedMonth,
                        'amount': amt,
                        'property': selectedProperty,
                      });
                      _employeeSalaries.insert(0, newSalary);
                    });

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Salary payment recorded!'), backgroundColor: Colors.green),
                    );
                  },
                  child: const Text('Record Salary'),
                ),
              ],
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
    final int totalSalary = _employeeSalaries.fold<int>(0, (sum, sal) => sum + (sal['amount'] as int? ?? 0));
    final filteredExpenses = _filteredExpenses;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final titleSection = const Text('Expenses & Salaries', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark));

              final addExpenseBtn = ElevatedButton.icon(
                onPressed: _showAddExpenseDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Expense'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(140, 44)),
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    const SizedBox(height: 12),
                    addExpenseBtn,
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  titleSection,
                  addExpenseBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Top Summary Row: 2 large cards: 'All Expenses' (Total Amount) and 'Employees Salary' (Total Salary)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final card1 = _buildSummaryCard(
                title: 'All Expenses',
                amount: '₹ $totalOtherExpenses',
                subtitle: '${_otherExpenses.length} operational entries',
                icon: Icons.receipt_long_outlined,
                iconColor: const Color(0xFFDC2626),
                iconBgColor: const Color(0xFFFEF2F2),
              );

              final card2 = _buildSummaryCard(
                title: 'Employees Salary',
                amount: '₹ $totalSalary',
                subtitle: '${_employeeSalaries.length} staff members payroll',
                icon: Icons.people_outline,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    card1,
                    const SizedBox(height: 12),
                    card2,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 16),
                  Expanded(child: card2),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // Section 1 - Other Expenses
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Other Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    SizedBox(height: 2),
                    Text('Utilities, maintenance, wifi, and grocery bills', style: TextStyle(fontSize: 12, color: AppTheme.textGrey), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showAddExpenseDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Expense', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Bar for Other Expenses
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search by description, category, property...',
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
            ),
          ),
          const SizedBox(height: 12),

          // Section 1 Table (DATE, CATEGORY, DESCRIPTION, AMOUNT, PROPERTY, ACTIONS)
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
                                exp['category'] ?? 'Utilities',
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
          const SizedBox(height: 32),

          // Section 2 - Employees Salary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Employees Salary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    SizedBox(height: 2),
                    Text('Cooks, housekeeping, security, and manager disbursements', style: TextStyle(fontSize: 12, color: AppTheme.textGrey), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showAddSalaryDialog,
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Record Salary', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Section 2 Table (EMPLOYEE NAME, PAYMENT DATE, SALARY MONTH, AMOUNT, PROPERTY, ACTIONS)
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
                        modernTableColumn('EMPLOYEE NAME'),
                        modernTableColumn('PAYMENT DATE'),
                        modernTableColumn('SALARY MONTH'),
                        modernTableColumn('AMOUNT'),
                        modernTableColumn('PROPERTY'),
                        modernTableColumn('ACTIONS'),
                      ],
                      rows: _employeeSalaries.map((sal) {
                        return DataRow(cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TableAvatar(name: sal['name'] ?? 'E', radius: 15),
                                const SizedBox(width: 10),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(sal['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                                    if (sal['role'] != null)
                                      Text(sal['role'], style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(sal['payment_date'] ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, fontWeight: FontWeight.w500)),
                          ),
                          DataCell(
                            Text(sal['salary_month'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                          ),
                          DataCell(
                            Text('₹ ${sal['amount']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                          ),
                          DataCell(
                            Text(sal['property'] ?? 'Green View PG - Hebbal', style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
                          ),
                          DataCell(
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textGrey),
                              tooltip: 'Actions',
                              onSelected: (val) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Downloading payslip for ${sal['name']}...')),
                                );
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'payslip', child: Text('Download Payslip', style: TextStyle(fontSize: 13))),
                                const PopupMenuItem(value: 'details', child: Text('View Details', style: TextStyle(fontSize: 13))),
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
