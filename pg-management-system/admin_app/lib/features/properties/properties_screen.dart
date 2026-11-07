import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';

import '../../core/services/admin_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/table_components.dart';
import 'property_form_dialog.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key});

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  List<Map<String, dynamic>> get _properties => AppData.properties;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  Future<void> _loadProperties() async {
    
    try {
      final props = await AdminApiService.getProperties();
      if (props.isNotEmpty && mounted) {
        AppData.setRealProperties(props);
      }
    } catch (e) {
      debugPrint('Failed to load properties from backend: $e');
    } finally {
      
    }
  }

  Future<void> _deletePropertyFromTable(Map<String, dynamic> prop) async {
    final propId = prop['id']?.toString();
    final propName = prop['name']?.toString() ?? 'Property';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $propName'),
        content: const Text('Are you sure you want to delete this property? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (propId != null && propId.isNotEmpty && !propId.startsWith('p')) {
        try {
          await AdminApiService.deleteProperty(propId);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete $propName: $e'), backgroundColor: Colors.red),
            );
          }
          return;
        }
      }
      setState(() {
        _properties.removeWhere((p) => (propId != null && p['id']?.toString() == propId) || p['name'] == prop['name']);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$propName deleted successfully!'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _showAddPropertyDialog() {
    showAddEditPropertyDialog(
      context: context,
      onSaved: () => _loadProperties(),
      onDeleted: () => _loadProperties(),
    );
  }

  void _showEditPropertyDialog(Map<String, dynamic> prop) {
    showAddEditPropertyDialog(
      context: context,
      property: prop,
      onSaved: () => _loadProperties(),
      onDeleted: () => _loadProperties(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalProperties = _properties.length;
    final totalRooms = _properties.fold<int>(0, (sum, p) => sum + ((p['rooms'] as int?) ?? 0));
    final totalBeds = _properties.fold<int>(0, (sum, p) => sum + ((p['beds'] as int?) ?? 0));
    final activeProperties = _properties.where((p) => p['status'] == 'Active').length;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - 'Manage Properties' on the left
          const Text(
            'Manage Properties',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),

          // 1. KPI Summary Cards (Total Properties, Total Rooms, Total Beds, Active Locations)
          TableKpiGrid(
            cards: [
              TableKpiCard(
                title: 'Total Properties',
                value: '$totalProperties',
                icon: Icons.apartment,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
              ),
              TableKpiCard(
                title: 'Total Rooms',
                value: '$totalRooms',
                icon: Icons.meeting_room_outlined,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
              ),
              TableKpiCard(
                title: 'Total Beds',
                value: '$totalBeds',
                icon: Icons.king_bed_outlined,
                iconColor: const Color(0xFF7C3AED),
                iconBgColor: const Color(0xFFF5F3FF),
              ),
              TableKpiCard(
                title: 'Active Locations',
                value: '$activeProperties',
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFFD97706),
                iconBgColor: const Color(0xFFFFFBEB),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // 2. Data Table
          Expanded(
            child: Container(
              decoration: modernTableDecoration,
              child: _properties.isEmpty
                  ? EmptyState(
                      icon: Icons.business,
                      title: 'No properties yet',
                      subtitle: 'Add your first PG to get started',
                      actionLabel: 'Add Property',
                      onAction: _showAddPropertyDialog,
                    )
                  : LayoutBuilder(
                      builder: (layoutCtx, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                dataRowMinHeight: 64,
                                dataRowMaxHeight: 70,
                                columnSpacing: 24,
                                horizontalMargin: 24,
                                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                headingRowHeight: 48,
                                dataRowColor: modernRowColor,
                                border: const TableBorder(
                                  horizontalInside: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                                ),
                                columns: [
                                  modernTableColumn('Property Name'),
                                  modernTableColumn('City'),
                                  modernTableColumn('Total Rooms'),
                                  modernTableColumn('Total Beds'),
                                  modernTableColumn('Status'),
                                  modernTableColumn('Actions'),
                                ],
                                rows: _properties.map((prop) {
                                  return DataRow(cells: [
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableAvatar(name: prop['name'] ?? 'P', radius: 17),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                prop['name'],
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 14),
                                              ),
                                              if (prop['type'] != null)
                                                Text(
                                                  prop['type'],
                                                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 11),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        prop['city'],
                                        style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${prop['rooms'] ?? 0} Rooms',
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${prop['beds'] ?? 0} Beds',
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
                                      ),
                                    ),
                                    DataCell(
                                      StatusPill(status: prop['status'] ?? 'Active'),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TableActionIconButton(
                                            tooltip: 'Edit Property',
                                            icon: Icons.edit_outlined,
                                            onPressed: () => _showEditPropertyDialog(prop),
                                          ),
                                          const SizedBox(width: 6),
                                          TableActionIconButton(
                                            tooltip: 'Delete Property',
                                            icon: Icons.delete_outline,
                                            color: Colors.red.shade400,
                                            onPressed: () => _deletePropertyFromTable(prop),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
