import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({super.key});

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _propertyData = {};

  @override
  void initState() {
    super.initState();
    _loadPropertyDetails();
  }

  Future<void> _loadPropertyDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await ResidentApiService.getPropertyDetails();
      if (mounted) {
        setState(() {
          _propertyData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resident = AppData.currentResident;
    final fallbackProperty = AppData.getPropertyByName(resident['property_name'] ?? resident['property'] ?? 'BNR Luxury PG');

    final propertyName = _propertyData['name'] ?? fallbackProperty['name'] ?? resident['property_name'] ?? 'BNR Luxury PG';

    final String address1 = _propertyData['address_line1']?.toString() ?? '';
    final String address2 = _propertyData['address_line2']?.toString() ?? '';
    final String city = _propertyData['city']?.toString() ?? '';
    final String state = _propertyData['state']?.toString() ?? '';
    final String pincode = _propertyData['pincode']?.toString() ?? '';

    final dynamic formattedAddressParts = [address1, address2, city, state, pincode]
        .where((e) => e.trim().isNotEmpty)
        .join(', ');

    final fullAddress = formattedAddressParts.isNotEmpty
        ? formattedAddressParts
        : (fallbackProperty['full_address'] ?? fallbackProperty['address'] ?? '#124, 5th Cross, 6th Block, Near Sony World Signal, Koramangala, Bengaluru, Karnataka - 560095');

    final propertySubtitle = city.isNotEmpty
        ? '$city, $state'
        : (fallbackProperty['address'] ?? 'Koramangala 6th Block, Bengaluru');

    final rawType = _propertyData['property_type'] ?? fallbackProperty['occupancyType'] ?? fallbackProperty['type'] ?? 'Co-Living PG';
    final occupancyType = rawType.toString().replaceAll('_', ' ').toUpperCase();

    final List<dynamic>? rawAmenities = _propertyData['amenities'] as List<dynamic>?;
    final amenities = (rawAmenities != null && rawAmenities.isNotEmpty)
        ? rawAmenities.map((e) => e.toString()).toList()
        : ((fallbackProperty['amenities'] as List?)?.map((e) => e.toString()).toList() ?? [
            'High Speed Wi-Fi',
            '3 Times Daily Meals',
            'Washing Machine',
            'Daily Housekeeping',
            'RO Drinking Water',
            'CCTV & Biometric Security',
            '24/7 Power Backup',
            'Common Lounge & TV',
            'AC / Cooler',
            'Parking',
          ]);

    final assignedRoom = _propertyData['assigned_room'] as Map<String, dynamic>?;
    final roomNumber = assignedRoom?['room_number'] ?? resident['room_number'] ?? resident['room'] ?? '101';

    String floor = '1st Floor';
    if (assignedRoom != null && assignedRoom['floor'] != null) {
      final f = assignedRoom['floor'].toString();
      floor = f == '0' ? 'Ground Floor' : '${f}th Floor';
    } else {
      final roomStr = roomNumber.toString();
      if (roomStr.length >= 3) {
        final floorDigit = roomStr[0];
        if (floorDigit == '1') floor = '1st Floor';
        if (floorDigit == '2') floor = '2nd Floor';
        if (floorDigit == '3') floor = '3rd Floor';
        if (floorDigit == '4') floor = '4th Floor';
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;

    void copyAddressToClipboard() {
      Clipboard.setData(ClipboardData(text: fullAddress));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Address copied to clipboard!'),
            ],
          ),
          backgroundColor: Color(0xFF059669),
          duration: Duration(seconds: 2),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      appBar: AppBar(
        title: Text(
          'Property Details',
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
            onPressed: _loadPropertyDetails,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadPropertyDetails,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Displaying cached property details (offline).',
                                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Property Hero Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              gradient: isDark ? AppTheme.cardShadeDarkGradient : AppTheme.heroCardGradient,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE0E7FF), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark ? const Color(0x1F000000) : const Color(0x144F46E5),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0x336366F1) : const Color(0x1A2563EB),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        occupancyType.endsWith('PG') ? occupancyType : '$occupancyType PG',
                                        style: TextStyle(
                                          color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified_rounded, size: 14, color: Color(0xFF059669)),
                                          SizedBox(width: 4),
                                          Text(
                                            'Verified PG',
                                            style: TextStyle(
                                              color: Color(0xFF059669),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  propertyName,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: textPri,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  propertySubtitle,
                                  style: TextStyle(
                                    color: textSec,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Room & Floor Stats
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: cardBg,
                                          borderRadius: BorderRadius.circular(16),
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
                                              child: Icon(Icons.bed_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 20),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Room Number', style: TextStyle(color: textSec, fontSize: 11), overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 2),
                                                  Text('Room $roomNumber', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPri), overflow: TextOverflow.ellipsis),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: cardBg,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: borderCol),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF4C1D95) : const Color(0xFFF5F3FF),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(Icons.apartment_rounded, color: Color(0xFF7C3AED), size: 20),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Floor', style: TextStyle(color: textSec, fontSize: 11), overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 2),
                                                  Text(floor, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPri), overflow: TextOverflow.ellipsis),
                                                ],
                                              ),
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
                          const SizedBox(height: 20),

                          // Full Address Card with Copy Button
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
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
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded, color: Color(0xFFEA580C), size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Full Property Address',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: textPri,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: copyAddressToClipboard,
                                      icon: Icon(Icons.copy_rounded, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 20),
                                      tooltip: 'Copy Address',
                                      style: IconButton.styleFrom(
                                        backgroundColor: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  fullAddress,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: textPri,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                InkWell(
                                  onTap: copyAddressToClipboard,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF243247) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.content_copy_rounded, size: 14, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Tap to copy full address for delivery or visitors',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Amenities & Inclusions
                          Text(
                            'Amenities & Inclusions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPri,
                            ),
                          ),
                          const SizedBox(height: 14),

                          if (amenities.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderCol),
                              ),
                              child: Center(
                                child: Text(
                                  'No amenities listed for this property.',
                                  style: TextStyle(color: textSec, fontSize: 13),
                                ),
                              ),
                            )
                          else
                            ...amenities.map((amenity) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderCol),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _getAmenityIcon(amenity),
                                        size: 20,
                                        color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        amenity,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: textPri,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  IconData _getAmenityIcon(String amenity) {
    final a = amenity.toLowerCase();
    if (a.contains('wi-fi') || a.contains('wifi') || a.contains('internet')) {
      return Icons.wifi_rounded;
    }
    if (a.contains('meal') || a.contains('food') || a.contains('mess') || a.contains('dining')) {
      return Icons.restaurant_rounded;
    }
    if (a.contains('washing') || a.contains('laundry')) {
      return Icons.local_laundry_service_rounded;
    }
    if (a.contains('cleaning') || a.contains('housekeeping')) {
      return Icons.cleaning_services_rounded;
    }
    if (a.contains('water') || a.contains('ro')) {
      return Icons.water_drop_rounded;
    }
    if (a.contains('cctv') || a.contains('security') || a.contains('biometric')) {
      return Icons.security_rounded;
    }
    if (a.contains('power') || a.contains('backup') || a.contains('electricity')) {
      return Icons.bolt_rounded;
    }
    if (a.contains('lounge') || a.contains('tv')) {
      return Icons.tv_rounded;
    }
    if (a.contains('ac') || a.contains('cooler') || a.contains('air condition')) {
      return Icons.ac_unit_rounded;
    }
    if (a.contains('parking') || a.contains('vehicle')) {
      return Icons.local_parking_rounded;
    }
    return Icons.check_circle_outline_rounded;
  }
}
