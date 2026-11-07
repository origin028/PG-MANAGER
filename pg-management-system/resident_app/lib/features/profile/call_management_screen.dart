import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class CallManagementScreen extends StatefulWidget {
  const CallManagementScreen({super.key});

  @override
  State<CallManagementScreen> createState() => _CallManagementScreenState();
}

class _CallManagementScreenState extends State<CallManagementScreen> {
  bool _isLoading = true;
  String _managerName = 'Rajesh Kumar';
  String _managerTitle = 'PG Owner • Available 8 AM - 10 PM';
  String _managerPhone = '9876543210';
  String _managerWhatsApp = '919876543210';

  String _caretakerName = 'Gate Security & Caretaker';
  String _caretakerTitle = '24/7 Desk';
  String _caretakerPhone = '9876543211';

  @override
  void initState() {
    super.initState();
    _loadPropertyContacts();
  }

  Future<void> _loadPropertyContacts() async {
    setState(() => _isLoading = true);
    try {
      final data = await ResidentApiService.getPropertyContacts();
      final contacts = data['contacts'] as List<dynamic>?;
      if (contacts != null && contacts.isNotEmpty) {
        for (var c in contacts) {
          final role = (c['role'] ?? '').toString().toUpperCase();
          final phone = (c['phone'] ?? '').toString();
          final name = (c['name'] ?? '').toString();
          final wa = (c['whatsapp_number'] ?? phone).toString();
          final timing = (c['timing_hours'] ?? '').toString();

          if (role.contains('MANAGER') || role.contains('OWNER')) {
            _managerName = name.isNotEmpty ? name : _managerName;
            _managerPhone = phone.isNotEmpty ? phone : _managerPhone;
            _managerWhatsApp = wa.isNotEmpty ? wa : _managerWhatsApp;
            if (timing.isNotEmpty) {
              _managerTitle = 'PG Owner • $timing';
            }
          } else if (role.contains('CARETAKER') || role.contains('WARDEN') || role.contains('SECURITY')) {
            _caretakerName = name.isNotEmpty ? '$name (Caretaker)' : _caretakerName;
            _caretakerPhone = phone.isNotEmpty ? phone : _caretakerPhone;
            if (timing.isNotEmpty) {
              _caretakerTitle = timing;
            }
          }
        }
      }
    } catch (_) {
      // Graceful fallback to default numbers if offline
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _makePhoneCall(BuildContext context, String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch dialer for $phone')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dialer error: $e')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String waNumber) async {
    final cleanWa = waNumber.replaceAll(RegExp(r'\D'), '');
    final Uri waUri = Uri.parse('https://wa.me/$cleanWa');
    try {
      if (await canLaunchUrl(waUri)) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp for $waNumber')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WhatsApp error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;
    final dividerCol = isDark ? AppTheme.darkBorder : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      appBar: AppBar(
        title: Text(
          'Call Management',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadPropertyContacts,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Primary PG Owner Card
                        Text(
                          'Property Owner',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textPri,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(22),
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
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF312E81) : const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(Icons.person_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _managerName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: textPri,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _managerTitle,
                                          style: TextStyle(fontSize: 12, color: textSec),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Divider(height: 1, color: dividerCol),
                              const SizedBox(height: 16),

                              // Phone Number Tile with Dialer Action
                              InkWell(
                                onTap: () => _makePhoneCall(context, _managerPhone),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF243247) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: borderCol),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.phone_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Owner Phone (Tap to Call)', style: TextStyle(color: textSec, fontSize: 11.5), overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 2),
                                            Text('+91 $_managerPhone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPri), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryBlue,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.call_rounded, size: 14, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text('Call', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // WhatsApp Tile with WhatsApp Launcher Action
                              InkWell(
                                onTap: () => _openWhatsApp(context, _managerWhatsApp),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF064E3B) : const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: isDark ? const Color(0xFF047857) : const Color(0xFFBBF7D0)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF065F46) : const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF22C55E), size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('WhatsApp Desk (Tap to Chat)', style: TextStyle(color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D), fontSize: 11.5), overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 2),
                                            Text('+91 $_managerPhone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: isDark ? Colors.white : const Color(0xFF166534)), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16A34A),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.send_rounded, size: 13, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text('Chat', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 2. Night Caretaker / Security Desk Card
                        Text(
                          'Night Caretaker & Security',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textPri,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
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
                          child: InkWell(
                            onTap: () => _makePhoneCall(context, _caretakerPhone),
                            borderRadius: BorderRadius.circular(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_caretakerName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPri), overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text('+91 $_caretakerPhone • $_caretakerTitle', style: TextStyle(fontSize: 12, color: textSec), overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _makePhoneCall(context, _caretakerPhone),
                                  icon: Icon(Icons.call_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 22),
                                  tooltip: 'Call Caretaker',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
