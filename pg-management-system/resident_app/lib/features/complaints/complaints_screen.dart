import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/motion_wrappers.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  bool _isLoading = false;
  String _selectedFilter = 'All';

  final List<String> _filterCategories = [
    'All',
    'Plumbing',
    'Electrical',
    'Wi-Fi',
    'Appliance',
    'Housekeeping',
    'General',
  ];

  // Default fallback mock complaints
  final List<Map<String, dynamic>> _complaints = [
    {
      'id': 'TKT-105',
      'title': 'AC remote not working & unit rattling',
      'category': 'Appliance',
      'priority': 'High',
      'status': 'In Progress',
      'date': 'Yesterday, 4:30 PM',
      'resolutionNote':
          'Technician assigned. Inspection scheduled for today at 3:00 PM.',
    },
    {
      'id': 'TKT-102',
      'title': 'Wi-Fi connection latency in Room during night',
      'category': 'Wi-Fi',
      'priority': 'Medium',
      'status': 'Resolved',
      'date': '24 Oct 2026',
      'resolutionNote': 'Secondary mesh repeater configured. Network latency tested below 15ms.',
    },
    {
      'id': 'TKT-098',
      'title': 'Bathroom tap dripping continuously',
      'category': 'Plumbing',
      'priority': 'Low',
      'status': 'Resolved',
      'date': '18 Oct 2026',
      'resolutionNote': 'Washer valve replaced by property plumber.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadComplaintsFromApi();
  }

  Future<void> _loadComplaintsFromApi() async {
    setState(() => _isLoading = true);
    try {
      final list = await ResidentApiService.getComplaints();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _complaints.clear();
          for (var c in list) {
            final rawStatus = (c['status'] ?? 'Pending').toString();
            final String normalizedStatus =
                rawStatus.toUpperCase() == 'RESOLVED'
                ? 'Resolved'
                : (rawStatus.toUpperCase().contains('PROGRESS')
                      ? 'In Progress'
                      : 'Pending');

            _complaints.add({
              'id': c['id'] != null
                  ? 'TKT-${c['id'].toString().substring(0, 4).toUpperCase()}'
                  : 'TKT-${100 + _complaints.length}',
              'title': c['title'] ?? c['description'] ?? 'Service Request',
              'category': c['category'] ?? 'General',
              'priority': c['priority'] ?? 'Medium',
              'status': normalizedStatus,
              'date':
                  c['created_at'] != null &&
                      c['created_at'].toString().length >= 10
                  ? c['created_at'].toString().substring(0, 10)
                  : 'Recent',
              'resolutionNote': c['resolution_note'] ?? c['admin_notes'],
            });
          }
        });
      }
    } catch (e) {
      debugPrint('API resident getComplaints error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRaiseComplaintModal() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedCategory = 'Plumbing';
    String selectedPriority = 'Medium';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        final isDark = HomeThemeTokens.isDark(modalCtx);
        final cardBg = isDark ? HomeThemeTokens.darkCardSurface : Colors.white;
        final borderCol = HomeThemeTokens.border(modalCtx);
        final textPri = HomeThemeTokens.textPrimary(modalCtx);
        final textSec = HomeThemeTokens.textSecondary(modalCtx);
        final tealCol = HomeThemeTokens.teal(modalCtx);
        final softTealCol = HomeThemeTokens.softTeal(modalCtx);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(modalCtx).size.height * 0.88,
                ),
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border.all(color: borderCol),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 28,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: borderCol,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: softTealCol,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.handyman_rounded,
                              color: tealCol,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Raise Service Request',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: textPri,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                Text(
                                  'Our property maintenance team will attend promptly',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: textSec,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(modalCtx),
                            icon: Icon(
                              Icons.close_rounded,
                              color: textSec,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Category Chips Selection
                      Text(
                        'Category',
                        style: HomeThemeTokens.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                              'Plumbing',
                              'Electrical',
                              'Wi-Fi',
                              'Appliance',
                              'Housekeeping',
                              'General',
                            ].map((cat) {
                              final isSelected = selectedCategory == cat;
                              return InkWell(
                                onTap: () =>
                                    setModalState(() => selectedCategory = cat),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? tealCol
                                        : (isDark
                                              ? const Color(0xFF1E272E)
                                              : const Color(0xFFF1F5F4)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? tealCol : borderCol,
                                    ),
                                  ),
                                  child: Text(
                                    cat,
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : textPri,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 18),

                      // Issue Title
                      Text(
                        'Issue Title',
                        style: HomeThemeTokens.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleController,
                        style: HomeThemeTokens.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPri,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Geyser not heating properly',
                          hintStyle: HomeThemeTokens.manrope(
                            fontSize: 13,
                            color: textSec,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF131F24)
                              : const Color(0xFFF7FAF9),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: tealCol, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      Text(
                        'Description',
                        style: HomeThemeTokens.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        style: HomeThemeTokens.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPri,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Describe details (e.g. Started yesterday, makes humming sound when switched on)...',
                          hintStyle: HomeThemeTokens.manrope(
                            fontSize: 13,
                            color: textSec,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF131F24)
                              : const Color(0xFFF7FAF9),
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: tealCol, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Priority Selection
                      Text(
                        'Priority Level',
                        style: HomeThemeTokens.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['Low', 'Medium', 'High'].map((p) {
                          final isSelected = selectedPriority == p;
                          Color activeColor = tealCol;
                          if (p == 'High') {
                            activeColor = const Color(0xFFE11D48);
                          }
                          if (p == 'Medium') {
                            activeColor = const Color(0xFFD97706);
                          }

                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: InkWell(
                                onTap: () =>
                                    setModalState(() => selectedPriority = p),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? activeColor.withValues(alpha: 0.15)
                                        : (isDark
                                              ? const Color(0xFF1E272E)
                                              : const Color(0xFFF1F5F4)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? activeColor
                                          : borderCol,
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      p,
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? activeColor
                                            : textSec,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final title = titleController.text.trim();
                                  final desc = descriptionController.text
                                      .trim();
                                  if (title.isEmpty) {
                                    ScaffoldMessenger.of(modalCtx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please enter an issue title',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSubmitting = true);

                                  String apiCategory = 'OTHER';
                                  final upperCat = selectedCategory
                                      .toUpperCase();
                                  if (upperCat.contains('PLUMB')) {
                                    apiCategory = 'PLUMBING';
                                  }
                                  if (upperCat.contains('ELECT')) {
                                    apiCategory = 'ELECTRICAL';
                                  }
                                  if (upperCat.contains('CLEAN') ||
                                      upperCat.contains('HOUSE')) {
                                    apiCategory = 'CLEANING';
                                  }
                                  if (upperCat.contains('WI') ||
                                      upperCat.contains('NET')) {
                                    apiCategory = 'WIFI';
                                  }
                                  if (upperCat.contains('FOOD')) {
                                    apiCategory = 'FOOD';
                                  }

                                  // Submit to backend
                                  ResidentApiService.createComplaint({
                                    'title': title,
                                    'description': desc.isNotEmpty
                                        ? desc
                                        : title,
                                    'category': apiCategory,
                                    'priority': selectedPriority.toUpperCase(),
                                  }).catchError((e) {
                                    debugPrint('API createComplaint error: $e');
                                    return <String, dynamic>{};
                                  });

                                  final newEntry = {
                                    'id': 'TKT-${106 + _complaints.length}',
                                    'title': title,
                                    'category': selectedCategory,
                                    'priority': selectedPriority,
                                    'status': 'Pending',
                                    'date': 'Just Now',
                                    'resolutionNote': null,
                                  };

                                  setState(() {
                                    _complaints.insert(0, newEntry);
                                  });
                                  AppData.complaints.insert(0, newEntry);

                                  Navigator.pop(modalCtx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        'Service request submitted successfully! Staff notified.',
                                      ),
                                      backgroundColor: tealCol,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tealCol,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Submit Request',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _getCategoryIcon(String? category) {
    final cat = (category ?? '').toLowerCase();
    if (cat.contains('plumb') || cat.contains('water') || cat.contains('tap')) {
      return Icons.water_drop_outlined;
    }
    if (cat.contains('elect') ||
        cat.contains('power') ||
        cat.contains('light')) {
      return Icons.bolt_outlined;
    }
    if (cat.contains('wi') || cat.contains('net') || cat.contains('router')) {
      return Icons.wifi_rounded;
    }
    if (cat.contains('appliance') ||
        cat.contains('ac') ||
        cat.contains('geyser')) {
      return Icons.hvac_rounded;
    }
    if (cat.contains('clean') ||
        cat.contains('housekeeping') ||
        cat.contains('room')) {
      return Icons.cleaning_services_rounded;
    }
    return Icons.handyman_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg = HomeThemeTokens.cardBg(context);
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);

    final filteredList = _selectedFilter == 'All'
        ? _complaints
        : _complaints.where((c) {
            final cat = (c['category'] ?? '').toString().toLowerCase();
            return cat.contains(_selectedFilter.toLowerCase());
          }).toList();

    final int totalCount = _complaints.length;
    final int inProgressCount = _complaints
        .where((c) => c['status'] == 'In Progress')
        .length;
    final int resolvedCount = _complaints
        .where((c) => c['status'] == 'Resolved')
        .length;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text(
          'Complaints & Services',
          style: HomeThemeTokens.manrope(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: textPri,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPri),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Requests',
            icon: Icon(Icons.refresh_rounded, color: textSec, size: 21),
            onPressed: _loadComplaintsFromApi,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              color: tealCol,
              backgroundColor: cardBg,
              onRefresh: _loadComplaintsFromApi,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18.0,
                  vertical: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isLoading)
                      LinearProgressIndicator(
                        color: tealCol,
                        backgroundColor: Colors.transparent,
                        minHeight: 2.5,
                      ),
                    // ========================================================
                    // 1. HERO SERVICE BANNER
                    // ========================================================
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF0D322E),
                                  const Color(0xFF133F3A),
                                ]
                              : [
                                  const Color(0xFFE6F4F1),
                                  const Color(0xFFD3EDE8),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1D5A52)
                              : const Color(0xFFB5E0D7),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: tealCol,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.support_agent_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '24/7 Property Maintenance',
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF063A34),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Report room issues, electrical, plumbing, or Wi-Fi problems instantly.',
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 12.5,
                                        height: 1.35,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? const Color(0xFFB0D5CF)
                                            : const Color(0xFF275953),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _showRaiseComplaintModal,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Raise Request'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: tealCol,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.push('/call-management'),
                                icon: Icon(
                                  Icons.phone_outlined,
                                  size: 17,
                                  color: tealCol,
                                ),
                                label: Text(
                                  'Call Desk',
                                  style: TextStyle(
                                    color: tealCol,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF246D63)
                                        : const Color(0xFF86CDC2),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ========================================================
                    // 2. SUMMARY METRICS ROW
                    // ========================================================
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Total',
                            count: totalCount,
                            color: tealCol,
                            bgColor: softTealCol,
                            isDark: isDark,
                            cardBg: cardBg,
                            borderCol: borderCol,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'In Progress',
                            count: inProgressCount,
                            color: const Color(0xFF0284C7),
                            bgColor: const Color(0xFFE0F2FE),
                            isDark: isDark,
                            cardBg: cardBg,
                            borderCol: borderCol,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Resolved',
                            count: resolvedCount,
                            color: HomeThemeTokens.success(context),
                            bgColor: HomeThemeTokens.successBg(context),
                            isDark: isDark,
                            cardBg: cardBg,
                            borderCol: borderCol,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ========================================================
                    // 3. CATEGORY FILTERS
                    // ========================================================
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filterCategories.map((cat) {
                          final isSelected = _selectedFilter == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _selectedFilter = cat),
                              borderRadius: BorderRadius.circular(99),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected ? tealCol : cardBg,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: isSelected ? tealCol : borderCol,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: tealCol.withValues(
                                              alpha: 0.25,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  cat,
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isSelected ? Colors.white : textSec,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ========================================================
                    // 4. TICKETS LIST
                    // ========================================================
                    if (filteredList.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: EmptyStateWidget(
                          title: 'No requests in $_selectedFilter',
                          subtitle: 'You have no tickets currently logged under this category.',
                          actionLabel: 'Raise New Request',
                          onAction: _showRaiseComplaintModal,
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredList.length,
                        itemBuilder: (context, idx) {
                          final comp = filteredList[idx];
                          final isResolved = comp['status'] == 'Resolved';
                          final isInProgress = comp['status'] == 'In Progress';
                          final isHigh = comp['priority'] == 'High';

                          Color statusColor;
                          Color statusBg;
                          IconData statusIcon;

                          if (isResolved) {
                            statusColor = HomeThemeTokens.success(context);
                            statusBg = HomeThemeTokens.successBg(context);
                            statusIcon = Icons.check_circle_rounded;
                          } else if (isInProgress) {
                            statusColor = const Color(0xFF0284C7);
                            statusBg = const Color(0xFFE0F2FE);
                            statusIcon = Icons.engineering_rounded;
                          } else {
                            statusColor = const Color(0xFFD97706);
                            statusBg = const Color(0xFFFEF3C7);
                            statusIcon = Icons.pending_actions_rounded;
                          }

                          return MotionEntrance(
                            delay: Duration(
                              milliseconds: (idx * 45).clamp(0, 200),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: borderCol),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? const Color(0x18000000)
                                        : const Color(0x060E1A1F),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: Category Icon & Name + Ticket ID + Date
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: softTealCol,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          _getCategoryIcon(comp['category']),
                                          color: tealCol,
                                          size: 19,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              comp['category'] ?? 'General',
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: textPri,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${comp['id'] ?? 'TKT'} • ${comp['date'] ?? 'Recent'}',
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: textSec,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Status Pill
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? statusColor.withValues(
                                                  alpha: 0.18,
                                                )
                                              : statusBg,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: statusColor.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              statusIcon,
                                              size: 12.5,
                                              color: statusColor,
                                            ),
                                            const SizedBox(width: 4.5),
                                            Text(
                                              comp['status'] ?? 'Pending',
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: statusColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Issue Title / Description
                                  Text(
                                    comp['title'] ??
                                        comp['issue'] ??
                                        'Maintenance Request',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: textPri,
                                      height: 1.35,
                                    ),
                                  ),

                                  // Resolution Note if present
                                  if (comp['resolutionNote'] != null &&
                                      comp['resolutionNote']
                                          .toString()
                                          .trim()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF142421)
                                            : const Color(0xFFF0FDF9),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isDark
                                              ? const Color(0xFF1B4E44)
                                              : const Color(0xFFB9EBDD),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.verified_outlined,
                                            size: 15,
                                            color: HomeThemeTokens.success(
                                              context,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              comp['resolutionNote'].toString(),
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: isDark
                                                    ? const Color(0xFFB0DBD2)
                                                    : const Color(0xFF165C51),
                                                height: 1.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 10),
                                  Divider(height: 1, color: borderCol),
                                  const SizedBox(height: 8),

                                  // Priority indicator footer
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isHigh
                                                    ? const Color(0xFFE11D48)
                                                    : const Color(0xFFD97706),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                '${comp['priority']} Priority',
                                                style: HomeThemeTokens.manrope(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: textSec,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Viewing request details for ${comp['id']}',
                                              ),
                                              duration: const Duration(
                                                seconds: 1,
                                              ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          child: Row(
                                            children: [
                                              Text(
                                                'Details',
                                                style: HomeThemeTokens.manrope(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: tealCol,
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 16,
                                                color: tealCol,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: HomeThemeTokens.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: HomeThemeTokens.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
