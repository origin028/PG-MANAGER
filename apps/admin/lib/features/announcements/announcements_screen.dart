import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/data/app_data.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedFilterPropertyId;
  bool? _selectedFilterActive;

  @override
  void initState() {
    super.initState();
    AppData.selectedPropertyIdNotifier.addListener(_onGlobalPropertyChange);
    _loadAnnouncements();
  }

  @override
  void dispose() {
    AppData.selectedPropertyIdNotifier.removeListener(_onGlobalPropertyChange);
    _searchController.dispose();
    super.dispose();
  }

  void _onGlobalPropertyChange() {
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final propId = _selectedFilterPropertyId ?? AppData.selectedPropertyId;
      final data = await AdminApiService.getAnnouncements(
        propertyId: propId != null && propId.isNotEmpty ? propId : null,
        isActive: _selectedFilterActive,
      );

      if (mounted) {
        setState(() {
          _announcements = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredAnnouncements {
    if (_searchQuery.trim().isEmpty) return _announcements;
    final q = _searchQuery.toLowerCase().trim();
    return _announcements.where((ann) {
      final title = (ann['title'] ?? '').toString().toLowerCase();
      final content = (ann['content'] ?? '').toString().toLowerCase();
      final propName = (ann['property_name'] ?? '').toString().toLowerCase();
      return title.contains(q) || content.contains(q) || propName.contains(q);
    }).toList();
  }

  void _showAnnouncementDialog({Map<String, dynamic>? existingAnnouncement}) {
    final isEditing = existingAnnouncement != null;
    final titleController = TextEditingController(
      text: existingAnnouncement != null ? (existingAnnouncement['title'] ?? '') : '',
    );
    final contentController = TextEditingController(
      text: existingAnnouncement != null ? (existingAnnouncement['content'] ?? '') : '',
    );

    String? selectedPropertyId = existingAnnouncement != null
        ? existingAnnouncement['property_id']?.toString()
        : (AppData.selectedPropertyId ?? '');
    bool isActive = existingAnnouncement != null ? (existingAnnouncement['is_active'] ?? true) : true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final properties = AppData.properties;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Modal Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.campaign_rounded, color: AppTheme.primaryBlue, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEditing ? 'Edit Announcement' : 'Create New Announcement',
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Publish announcements visible to residents of target properties',
                                    style: GoogleFonts.manrope(fontSize: 12.5, color: AppTheme.textGrey),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20, color: AppTheme.textGrey),
                              onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 20),

                        // Title field
                        Text(
                          'Announcement Title *',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            hintText: 'e.g., Scheduled Water Tank Maintenance',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Target Property Dropdown
                        Text(
                          'Target Property',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: (selectedPropertyId != null && selectedPropertyId!.isNotEmpty) ? selectedPropertyId : null,
                              hint: const Text('All Properties (Company-wide)', style: TextStyle(fontSize: 13, color: AppTheme.textDark)),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Properties (Company-wide)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                                ...properties.map((p) {
                                  return DropdownMenuItem<String?>(
                                    value: p['id']?.toString(),
                                    child: Text(p['name']?.toString() ?? 'Property', style: const TextStyle(fontSize: 13)),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setDialogState(() => selectedPropertyId = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Message / Content
                        Text(
                          'Announcement Content / Message *',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: contentController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Enter full announcement details for residents...',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Status toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Status',
                                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                                ),
                                Text(
                                  isActive ? 'Published (Visible to residents)' : 'Draft / Inactive (Hidden from residents)',
                                  style: GoogleFonts.manrope(fontSize: 12, color: isActive ? const Color(0xFF16A34A) : AppTheme.textGrey),
                                ),
                              ],
                            ),
                            Switch.adaptive(
                              value: isActive,
                              activeThumbColor: AppTheme.primaryTeal,
                              onChanged: (val) {
                                setDialogState(() => isActive = val);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      final title = titleController.text.trim();
                                      final content = contentController.text.trim();
                                      if (title.isEmpty || content.isEmpty) {
                                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                                          const SnackBar(content: Text('Please enter title and content'), backgroundColor: AppTheme.statusRed),
                                        );
                                        return;
                                      }

                                      setDialogState(() => isSubmitting = true);
                                      try {
                                        await TokenStorage.ensureInitialized();
                                        if (!TokenStorage.isAuthenticated) {
                                          throw Exception('Administrator session required. Please sign in to publish announcements.');
                                        }

                                        final payload = {
                                          'title': title,
                                          'content': content,
                                          'property_id': (selectedPropertyId != null && selectedPropertyId!.isNotEmpty) ? selectedPropertyId : null,
                                          'is_active': isActive,
                                        };

                                        if (isEditing) {
                                          final id = existingAnnouncement['id'].toString();
                                          await AdminApiService.updateAnnouncement(id, payload);
                                        } else {
                                          await AdminApiService.createAnnouncement(payload);
                                        }

                                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                                        _loadAnnouncements();
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            SnackBar(
                                              content: Text(isEditing ? 'Announcement updated successfully!' : 'Announcement published successfully!'),
                                              backgroundColor: AppTheme.successGreen,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        setDialogState(() => isSubmitting = false);
                                        final cleanMsg = e.toString().replaceAll('Exception: ', '').replaceAll('ApiException: ', '');
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                                            SnackBar(content: Text('Failed to save announcement: $cleanMsg'), backgroundColor: AppTheme.statusRed),
                                          );
                                        }
                                      }
                                    },
                              icon: isSubmitting
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_rounded, size: 16),
                              label: Text(
                                isSubmitting ? 'Saving...' : (isEditing ? 'Save Changes' : 'Publish Announcement'),
                                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAnnouncement(Map<String, dynamic> ann) {
    final id = ann['id']?.toString() ?? '';
    final title = ann['title']?.toString() ?? 'this announcement';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Announcement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to permanently delete "$title"? Residents will no longer see it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AdminApiService.deleteAnnouncement(id);
                _loadAnnouncements();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Announcement deleted successfully.'), backgroundColor: AppTheme.successGreen),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete announcement: $e'), backgroundColor: AppTheme.statusRed),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusRed, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _toggleStatus(Map<String, dynamic> ann) async {
    final id = ann['id']?.toString() ?? '';
    final currentStatus = ann['is_active'] == true;
    final newStatus = !currentStatus;

    try {
      await AdminApiService.updateAnnouncementStatus(id, newStatus);
      _loadAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'Announcement activated & published.' : 'Announcement marked inactive.'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: AppTheme.statusRed),
        );
      }
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Recent';
    final str = raw.toString();
    try {
      final dt = DateTime.parse(str);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return str.length >= 10 ? str.substring(0, 10) : str;
    }
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
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
        boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.manrope(fontSize: 11.5, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAnnouncements;
    final totalCount = _announcements.length;
    final activeCount = _announcements.where((a) => a['is_active'] == true).length;
    final properties = AppData.properties;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Announcements',
                    style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage and broadcast property notices to residents in real-time',
                    style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textGrey),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showAnnouncementDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Announcement', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // KPI Summary Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final card1 = _buildSummaryCard(
                title: 'Total Announcements',
                value: '$totalCount',
                subtitle: 'Published across properties',
                icon: Icons.campaign_rounded,
                iconColor: AppTheme.primaryBlue,
                iconBgColor: const Color(0xFFEFF6FF),
              );
              final card2 = _buildSummaryCard(
                title: 'Active / Published',
                value: '$activeCount',
                subtitle: 'Visible to resident apps',
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              );
              final card3 = _buildSummaryCard(
                title: 'Draft / Inactive',
                value: '${totalCount - activeCount}',
                subtitle: 'Hidden from residents',
                icon: Icons.visibility_off_outlined,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFEF3C7),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: card1),
                    const SizedBox(width: 16),
                    Expanded(child: card2),
                    const SizedBox(width: 16),
                    Expanded(child: card3),
                  ],
                );
              }
              return Column(
                children: [
                  card1,
                  const SizedBox(height: 12),
                  card2,
                  const SizedBox(height: 12),
                  card3,
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Search and Filters Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 750;

                final searchField = TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search announcements by title, content, or property...',
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                );

                final propertyFilter = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedFilterPropertyId,
                      hint: const Text('Filter Property: All', style: TextStyle(fontSize: 13, color: AppTheme.textDark)),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Properties', style: TextStyle(fontSize: 13))),
                        ...properties.map((p) => DropdownMenuItem<String?>(value: p['id']?.toString(), child: Text(p['name']?.toString() ?? 'Property', style: const TextStyle(fontSize: 13)))),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedFilterPropertyId = val);
                        _loadAnnouncements();
                      },
                    ),
                  ),
                );

                final refreshBtn = IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.textGrey),
                  tooltip: 'Refresh',
                  onPressed: _loadAnnouncements,
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: propertyFilter),
                          const SizedBox(width: 8),
                          refreshBtn,
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 14),
                    propertyFilter,
                    const SizedBox(width: 8),
                    refreshBtn,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Main Table or Empty/Loading State
          if (_isLoading)
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primaryTeal),
                    SizedBox(height: 14),
                    Text('Loading announcements...', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.statusRed, size: 36),
                    const SizedBox(height: 12),
                    Text('Failed to load announcements', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(_errorMessage!, style: const TextStyle(color: AppTheme.textGrey, fontSize: 13), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadAnnouncements,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(32)),
                      child: const Icon(Icons.campaign_outlined, color: AppTheme.primaryBlue, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty ? 'No announcements matching "$_searchQuery"' : 'No announcements published yet',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _searchQuery.isNotEmpty ? 'Try adjusting your search keywords or property filters' : 'Create announcements to broadcast important notices directly to residents',
                      style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textGrey),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _showAnnouncementDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create First Announcement'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 850),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      headingTextStyle: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF64748B), letterSpacing: 0.5),
                      dataTextStyle: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textDark),
                      columnSpacing: 24,
                      horizontalMargin: 20,
                      columns: const [
                        DataColumn(label: Text('ANNOUNCEMENT')),
                        DataColumn(label: Text('PROPERTY')),
                        DataColumn(label: Text('CONTENT PREVIEW')),
                        DataColumn(label: Text('DATE')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: filtered.map((ann) {
                        final title = ann['title']?.toString() ?? 'Announcement';
                        final content = ann['content']?.toString() ?? '';
                        final propName = ann['property_name']?.toString() ?? 'All Properties';
                        final dateStr = _formatDate(ann['created_at']);
                        final isActive = ann['is_active'] == true;

                        return DataRow(
                          cells: [
                            // Title
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: isActive ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.campaign_rounded, size: 18, color: isActive ? AppTheme.primaryBlue : AppTheme.textGrey),
                                  ),
                                  const SizedBox(width: 10),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Property Badge
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: propName == 'All Properties' ? const Color(0xFFF5F3FF) : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: propName == 'All Properties' ? const Color(0xFFDDD6FE) : const Color(0xFFBBF7D0),
                                  ),
                                ),
                                child: Text(
                                  propName,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: propName == 'All Properties' ? const Color(0xFF7C3AED) : const Color(0xFF15803D),
                                  ),
                                ),
                              ),
                            ),

                            // Content Preview
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 240),
                                child: Text(
                                  content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                                ),
                              ),
                            ),

                            // Date
                            DataCell(Text(dateStr, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5))),

                            // Status Chip
                            DataCell(
                              InkWell(
                                onTap: () => _toggleStatus(ann),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: isActive ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isActive ? 'Published' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isActive ? const Color(0xFF059669) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Actions
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryBlue),
                                    tooltip: 'Edit announcement',
                                    onPressed: () => _showAnnouncementDialog(existingAnnouncement: ann),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.statusRed),
                                    tooltip: 'Delete announcement',
                                    onPressed: () => _confirmDeleteAnnouncement(ann),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
