import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/services/resident_api_service.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late final List<Map<String, dynamic>> _notices;

  @override
  void initState() {
    super.initState();
    _notices = [
      {
        'id': 'NOTIF-1',
        'title': 'Water supply maintenance',
        'description': 'Water will be off tomorrow from 10:00 AM to 2:00 PM for solar pipeline servicing.',
        'category': 'Facility',
        'date': 'Today, 10:00 AM',
        'icon': Icons.water_drop_rounded,
        'isImportant': true,
      },
      {
        'id': 'NOTIF-3',
        'title': 'High-Speed Wi-Fi Upgrade',
        'description': 'Mesh router firmware across Floor 1 and Floor 2 has been upgraded to 300 Mbps bandwidth.',
        'category': 'Internet',
        'date': '24 Oct 2026',
        'icon': Icons.wifi_rounded,
        'isImportant': false,
      },
      {
        'id': 'NOTIF-4',
        'title': 'Visitor Timing Reminder',
        'description': 'Visitors and guests are allowed in the common lounge area until 9:00 PM daily.',
        'category': 'Rules',
        'date': '20 Oct 2026',
        'icon': Icons.schedule_rounded,
        'isImportant': false,
      },
      {
        'id': 'NOTIF-5',
        'title': 'Scheduled Pest Control Drive',
        'description': 'Bi-monthly pest control and deep cleaning will be conducted this Sunday from 11:00 AM.',
        'category': 'Maintenance',
        'date': '18 Oct 2026',
        'icon': Icons.cleaning_services_rounded,
        'isImportant': false,
      },
    ];
    _loadNoticesFromApi();
  }

  void _loadNoticesFromApi() async {
    try {
      final list = await ResidentApiService.getNotices();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _notices.clear();
          for (var n in list) {
            _notices.add({
              'id': n['id']?.toString() ?? '',
              'title': n['title'] ?? 'Notice',
              'description': n['message'] ?? '',
              'category': 'Notice',
              'date': n['created_at']?.toString().substring(0, 10) ?? 'Recent',
              'icon': Icons.campaign_rounded,
              'isImportant': (n['priority'] == 'HIGH' || n['priority'] == 'URGENT'),
            });
          }
        });
      }
    } catch (e) {
      debugPrint('API getNotices error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final borderCol = AppTheme.borderCol(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final pageBg = AppTheme.pageBg(context);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text('Notices & Circulars', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPri)),
        backgroundColor: cardBg,
        iconTheme: IconThemeData(color: textPri),
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
          if (_notices.isNotEmpty)
            IconButton(
              tooltip: 'Clear for Empty State Preview',
              icon: Icon(Icons.delete_sweep_outlined, color: textSec, size: 22),
              onPressed: () {
                setState(() => _notices.clear());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notices cleared to preview Empty State with Lottie animation')),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _notices.isEmpty
                ? EmptyStateWidget(
                    title: 'Nothing Here Yet',
                    subtitle: 'No data found for your request.',
                    actionLabel: 'Refresh Notices',
                    onAction: () {
                      setState(() {
                        _notices.addAll([
                          {
                            'id': 'NOTIF-1',
                            'title': 'Water supply maintenance',
                            'description': 'Water will be off tomorrow from 10:00 AM to 2:00 PM.',
                            'category': 'Facility',
                            'date': 'Today, 10:00 AM',
                            'icon': Icons.water_drop_rounded,
                            'isImportant': true,
                          },
                          {
                            'id': 'NOTIF-3',
                            'title': 'High-Speed Wi-Fi Upgrade',
                            'description': 'Mesh router bandwidth upgraded to 300 Mbps.',
                            'category': 'Internet',
                            'date': '24 Oct 2026',
                            'icon': Icons.wifi_rounded,
                            'isImportant': false,
                          },
                        ]);
                      });
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    itemCount: _notices.length,
                    itemBuilder: (context, index) {
                      final item = _notices[index];
                      final isImportant = item['isImportant'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isImportant ? const Color(0x4D4F46E5) : borderCol,
                            width: isImportant ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? const Color(0x1A000000) : const Color(0x05000000),
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
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isImportant ? (isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF)) : (isDark ? const Color(0xFF1E293B) : AppTheme.softGrey),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item['category'],
                                        style: TextStyle(
                                          color: isImportant ? (isDark ? const Color(0xFFA5B4FC) : AppTheme.primaryBlue) : textSec,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isImportant) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFECEF),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Important',
                                          style: TextStyle(
                                            color: AppTheme.accentPink,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  item['date'],
                                  style: TextStyle(fontSize: 12, color: textSec),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              item['title'],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textPri,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['description'],
                              style: TextStyle(
                                fontSize: 13,
                                color: textSec,
                                height: 1.4,
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
