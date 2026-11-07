import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state_widget.dart';

class AllComplaintsScreen extends StatefulWidget {
  const AllComplaintsScreen({super.key});

  @override
  State<AllComplaintsScreen> createState() => _AllComplaintsScreenState();
}

class _AllComplaintsScreenState extends State<AllComplaintsScreen> {
  final List<Map<String, dynamic>> _complaints = [
    {
      'id': 'CMP-101',
      'title': 'AC not cooling',
      'category': 'Appliance',
      'date': '28 Oct 2026',
      'status': 'Resolved',
      'resolutionNote': 'Gas refilled by technician. Cooling tested normal.',
    },
    {
      'id': 'CMP-102',
      'title': 'Bathroom tap leaking',
      'category': 'Plumbing',
      'date': '22 Oct 2026',
      'status': 'Resolved',
      'resolutionNote': 'Washer valve replaced by maintenance staff.',
    },
    {
      'id': 'CMP-103',
      'title': 'Wi-Fi latency on Floor 1',
      'category': 'Wi-Fi/Internet',
      'date': '15 Oct 2026',
      'status': 'Resolved',
      'resolutionNote': 'Secondary repeater configured and mesh channel updated.',
    },
    {
      'id': 'CMP-104',
      'title': 'Geyser heating delay',
      'category': 'Electrical',
      'date': '08 Oct 2026',
      'status': 'Resolved',
      'resolutionNote': 'Heating coil descaled and thermostat reset.',
    },
  ];

  void _showClearConfirmationDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.transparent),
        ),
        title: Text(
          'Clear Complaint History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : AppTheme.textDark,
          ),
        ),
        content: Text(
          'Are you sure you want to clear your complaint history?',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _complaints.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('History cleared'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Clear All', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;
    final pageBg = isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text(
          'Complaint History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: textPri,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPri),
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
          if (_complaints.isNotEmpty)
            TextButton(
              onPressed: _showClearConfirmationDialog,
              child: const Text(
                'Clear All',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _complaints.isEmpty
                ? EmptyStateWidget(
                    title: 'No complaints found',
                    subtitle: 'You have no past or resolved complaints at this time.',
                    actionLabel: 'Refresh History',
                    onAction: () {
                      setState(() {
                        _complaints.addAll([
                          {
                            'id': 'CMP-101',
                            'title': 'AC not cooling',
                            'category': 'Appliance',
                            'date': '28 Oct 2026',
                            'status': 'Resolved',
                            'resolutionNote': 'Gas refilled by technician.',
                          },
                        ]);
                      });
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    itemCount: _complaints.length,
                    itemBuilder: (context, index) {
                      final item = _complaints[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderCol),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Category + Resolved badge & Date
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item['category'] ?? 'Complaint',
                                        style: TextStyle(
                                          color: textSec,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            size: 13,
                                            color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Resolved',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  item['date'] ?? '',
                                  style: TextStyle(fontSize: 12, color: textSec, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Issue Title
                            Text(
                              item['title'] ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textPri,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Admin's resolution note
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F2B26) : const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF115E59) : const Color(0xFFBBF7D0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 16,
                                    color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF047857),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Admin Note: ${item['resolutionNote'] ?? 'Resolved by property administration.'}',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: isDark ? const Color(0xFFCCFBF1) : const Color(0xFF065F46),
                                        height: 1.35,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
