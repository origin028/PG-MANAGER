import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/services/resident_api_service.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  @override
  void initState() {
    super.initState();
    _loadComplaintsFromApi();
  }

  void _loadComplaintsFromApi() async {
    try {
      final list = await ResidentApiService.getComplaints();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _complaints.clear();
          for (var c in list) {
            _complaints.add({
              'id': c['id']?.toString() ?? '',
              'issue': c['description'] ?? c['title'] ?? 'Complaint',
              'category': c['category'] ?? 'General',
              'priority': c['priority'] ?? 'Medium',
              'status': c['status'] == 'RESOLVED' ? 'Resolved' : (c['status'] == 'IN_PROGRESS' ? 'In Progress' : 'Pending'),
              'date': c['created_at']?.toString().substring(0, 10) ?? 'Recent',
            });
          }
        });
      }
    } catch (e) {
      debugPrint('API resident getComplaints error: $e');
    }
  }

  // Mock Data for Complaints
  final List<Map<String, dynamic>> _complaints = [
    {
      'id': 'TKT-105',
      'issue': 'Air conditioner remote not responding and making rattling sound',
      'category': 'Appliance',
      'priority': 'High',
      'status': 'In Progress',
      'date': 'Yesterday, 4:30 PM',
    },
    {
      'id': 'TKT-102',
      'issue': 'Wi-Fi connection latency in Room 101 during night hours',
      'category': 'Internet',
      'priority': 'Medium',
      'status': 'Resolved',
      'date': '24 Oct 2026',
    },
  ];

  void _showRaiseComplaintModal() {
    final issueController = TextEditingController();
    String selectedPriority = 'Medium';
    String selectedCategory = 'Maintenance';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(modalCtx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Icon(Icons.report_problem_rounded, color: AppTheme.primaryBlue, size: 24),
                        SizedBox(width: 10),
                        Text('Raise a Complaint', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Our PG maintenance staff will be dispatched promptly.', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                    const SizedBox(height: 20),

                    const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.softGrey,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      items: ['Maintenance', 'Appliance', 'Plumbing', 'Electrical', 'Internet', 'Housekeeping']
                          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onChanged: (val) => setModalState(() => selectedCategory = val!),
                    ),
                    const SizedBox(height: 16),

                    const Text('Issue Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: issueController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Describe your issue (e.g. Water heater in 2nd floor bathroom not turning on)...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.softGrey,
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text('Priority Level', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPriority,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.softGrey,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      items: ['Low', 'Medium', 'High']
                          .map((p) => DropdownMenuItem(value: p, child: Text('$p Priority', style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onChanged: (val) => setModalState(() => selectedPriority = val!),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: () {
                        if (issueController.text.trim().isEmpty) return;

                        setState(() {
                          _complaints.insert(0, {
                            'id': 'TKT-${106 + _complaints.length}',
                            'issue': issueController.text.trim(),
                            'category': selectedCategory,
                            'priority': selectedPriority,
                            'status': 'Pending',
                            'date': 'Just Now',
                          });
                        });
                        Navigator.pop(modalCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ticket created successfully!'), backgroundColor: Colors.green),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Submit Complaint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundWhite,
      appBar: AppBar(
        title: const Text('Complaints & Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_complaints.isNotEmpty)
            IconButton(
              tooltip: 'Clear for Empty State Preview',
              icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.textGrey, size: 22),
              onPressed: () {
                setState(() => _complaints.clear());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Complaints cleared to preview Empty State with Lottie animation')),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _complaints.isEmpty
                // ========================================================
                // STEP 5: ADD LOTTIE ANIMATION FOR EMPTY STATE
                // 'Nothing Here Yet' and 'No data found for your request.'
                // ========================================================
                ? EmptyStateWidget(
                    title: 'Nothing Here Yet',
                    subtitle: 'No data found for your request.',
                    actionLabel: 'Raise Complaint',
                    onAction: _showRaiseComplaintModal,
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'My Tickets',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showRaiseComplaintModal,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Raise New'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(120, 42),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Complaint Items List
                        ..._complaints.map((comp) {
                          final isResolved = comp['status'] == 'Resolved';
                          final isHigh = comp['priority'] == 'High';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFEDF2F7)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0x05000000),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.softGrey,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        comp['id'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 12),
                                      ),
                                    ),
                                    Text(comp['date'], style: const TextStyle(color: AppTheme.textLight, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  comp['issue'],
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textDark, height: 1.35),
                                ),
                                const SizedBox(height: 16),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Priority Pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isHigh ? const Color(0xFFFFECEF) : const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${comp['priority']} Priority',
                                        style: TextStyle(
                                          color: isHigh ? AppTheme.accentPink : AppTheme.primaryBlue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),

                                    // Status Pill
                                    Row(
                                      children: [
                                        Icon(
                                          isResolved ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                                          size: 16,
                                          color: isResolved ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          comp['status'],
                                          style: TextStyle(
                                            color: isResolved ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
