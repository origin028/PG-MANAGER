import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({super.key});

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _propertyData = {};

  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loadPropertyDetails();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _triggerEntranceAnimation() {
    if (!mounted) return;
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) {
      _entranceController.value = 1.0;
    } else {
      _entranceController.forward(from: 0.0);
    }
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
        _triggerEntranceAnimation();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
        _triggerEntranceAnimation();
      }
    }
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (GoRouter.maybeOf(context) != null) {
      context.go('/menu');
    }
  }

  Widget _staggeredEntrance({
    required double begin,
    required double end,
    required Widget child,
  }) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        begin.clamp(0.0, 0.96),
        end.clamp(0.05, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, inner) {
        final t = anim.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: inner,
          ),
        );
      },
    );
  }

  String _formatOrdinalFloor(dynamic rawFloor) {
    final parsed = int.tryParse(rawFloor.toString().trim());
    if (parsed == null) return '${rawFloor.toString()} Floor';
    if (parsed == 0) return 'Ground Floor';
    final mod100 = parsed % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${parsed}th Floor';
    switch (parsed % 10) {
      case 1:
        return '${parsed}st Floor';
      case 2:
        return '${parsed}nd Floor';
      case 3:
        return '${parsed}rd Floor';
      default:
        return '${parsed}th Floor';
    }
  }

  @override
  Widget build(BuildContext context) {
    final resident = AppData.currentResident;
    final fallbackProperty = AppData.getPropertyByName(
      resident['property_name'] ?? resident['property'] ?? 'BNR Luxury PG',
    );

    final propertyName = (_propertyData['name'] ??
            fallbackProperty['name'] ??
            resident['property_name'] ??
            'BNR Luxury PG')
        .toString();

    final String address1 = _propertyData['address_line1']?.toString() ?? '';
    final String address2 = _propertyData['address_line2']?.toString() ?? '';
    final String city = _propertyData['city']?.toString() ?? '';
    final String state = _propertyData['state']?.toString() ?? '';
    final String pincode = _propertyData['pincode']?.toString() ?? '';

    final String formattedAddressParts = [
      address1,
      address2,
      city,
      state,
      pincode,
    ].where((e) => e.trim().isNotEmpty).join(', ');

    final String fullAddress = (formattedAddressParts.isNotEmpty
            ? formattedAddressParts
            : (fallbackProperty['full_address'] ??
                fallbackProperty['address'] ??
                '#124, 5th Cross, 6th Block, Near Sony World Signal, Koramangala, Bengaluru, Karnataka - 560095'))
        .toString();

    final String propertySubtitle = (city.isNotEmpty
            ? '$city, $state'
            : (fallbackProperty['address'] ?? 'Koramangala 6th Block, Bengaluru'))
        .toString();

    final rawType = _propertyData['property_type'] ??
        fallbackProperty['occupancyType'] ??
        fallbackProperty['type'] ??
        'Co-Living PG';
    final occupancyType =
        rawType.toString().replaceAll('_', ' ').toUpperCase();

    final List<dynamic>? rawAmenities =
        _propertyData['amenities'] as List<dynamic>?;
    final amenities = (rawAmenities != null && rawAmenities.isNotEmpty)
        ? rawAmenities.map((e) => e.toString()).toList()
        : ((fallbackProperty['amenities'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [
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

    final assignedRoom =
        _propertyData['assigned_room'] as Map<String, dynamic>?;
    final assignedBed =
        _propertyData['assigned_bed'] as Map<String, dynamic>?;

    final roomNumber = (assignedRoom?['room_number'] ??
            resident['room_number'] ??
            resident['room'] ??
            '101')
        .toString();

    final String? bedNumber = (assignedBed?['bed_number'] ?? resident['bed'])
        ?.toString()
        .trim();

    String floor = '1st Floor';
    if (assignedRoom != null && assignedRoom['floor'] != null) {
      floor = _formatOrdinalFloor(assignedRoom['floor']);
    } else {
      final roomStr = roomNumber;
      if (roomStr.length >= 3) {
        final floorDigit = int.tryParse(roomStr[0]);
        if (floorDigit != null) {
          floor = _formatOrdinalFloor(floorDigit);
        }
      }
    }

    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final cardShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x20000000) : const Color(0x0A0E1A1F),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ];

    final heroShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x38000000) : const Color(0x240B2231),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];

    void copyAddressToClipboard() {
      Clipboard.setData(ClipboardData(text: fullAddress));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Address copied to clipboard!')),
            ],
          ),
          backgroundColor: HomeThemeTokens.lightTeal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            // ----------------------------------------------------------------
            // 1. TOP HEADER BAR
            // ----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Row(
                    children: [
                      _InteractivePress(
                        onTap: _handleBack,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: borderCol, width: 1),
                            boxShadow: cardShadow,
                          ),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: textPri,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Property Details',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeThemeTokens.manrope(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: textPri,
                          ),
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: borderCol, width: 1),
                          boxShadow: cardShadow,
                        ),
                        child: _InteractivePress(
                          child: IconButton(
                            icon: Icon(
                              Icons.refresh_rounded,
                              size: 19,
                              color: textPri,
                            ),
                            tooltip: 'Refresh',
                            padding: EdgeInsets.zero,
                            onPressed: _loadPropertyDetails,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ----------------------------------------------------------------
            // 2. MAIN CONTENT
            // ----------------------------------------------------------------
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: tealCol),
                    )
                  : RefreshIndicator(
                      color: tealCol,
                      onRefresh: _loadPropertyDetails,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_errorMessage != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: HomeThemeTokens.warningBg(context),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: HomeThemeTokens.warning(context)
                                            .withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          color:
                                              HomeThemeTokens.warning(context),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(
                                            'Displaying cached property details (offline).',
                                            style: HomeThemeTokens.manrope(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: HomeThemeTokens.warning(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // --------------------------------------------
                                // PROPERTY HERO CARD
                                // --------------------------------------------
                                _staggeredEntrance(
                                  begin: 0.05,
                                  end: 0.45,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient:
                                          HomeThemeTokens.heroGradient(context),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.08),
                                        width: 1,
                                      ),
                                      boxShadow: heroShadow,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(21),
                                      child: Stack(
                                        children: [
                                          // Subtle dot matrix texture matching reference
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: CustomPaint(
                                                painter: _HeroDotGridPainter(),
                                              ),
                                            ),
                                          ),

                                          // Architectural building vector illustration
                                          Positioned(
                                            right: 18,
                                            top: 46,
                                            child: IgnorePointer(
                                              child: _HeroBuildingGraphic(
                                                highlightFloorColor:
                                                    const Color(0xFF2FB8A3),
                                              ),
                                            ),
                                          ),

                                          Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    right: 82,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      // Occupancy Type Pill
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 11,
                                                          vertical: 5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withValues(
                                                            alpha: 0.14,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            999,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          occupancyType
                                                                  .endsWith('PG')
                                                              ? occupancyType
                                                              : '$occupancyType PG',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: HomeThemeTokens
                                                              .manrope(
                                                            color: Colors.white,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      // Large Property Name
                                                      Text(
                                                        propertyName,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Colors.white,
                                                          letterSpacing: -0.6,
                                                          height: 1.12,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 5),
                                                      // Location Subtitle
                                                      Text(
                                                        propertySubtitle,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          color: const Color(
                                                            0xFFB7C6D2,
                                                          ),
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          height: 1.35,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      // Verification Chip
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 11,
                                                          vertical: 5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: HomeThemeTokens
                                                              .successBg(
                                                            context,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            999,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .check_rounded,
                                                              size: 13.5,
                                                              color: HomeThemeTokens
                                                                  .success(
                                                                context,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 5,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                'Verified PG',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    HomeThemeTokens
                                                                        .manrope(
                                                                  color: HomeThemeTokens
                                                                      .success(
                                                                    context,
                                                                  ),
                                                                  fontSize: 11.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 16),

                                                // Room & Floor Translucent Stat Tiles
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _buildHeroStatTile(
                                                        icon: Icons.bed_rounded,
                                                        label: 'Room Number',
                                                        value: (bedNumber !=
                                                                    null &&
                                                                bedNumber
                                                                    .isNotEmpty)
                                                            ? '$roomNumber · ${bedNumber.replaceFirst(RegExp(r'^Bed\s+', caseSensitive: false), '')}'
                                                            : roomNumber,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: _buildHeroStatTile(
                                                        icon: Icons
                                                            .apartment_rounded,
                                                        label: 'Floor',
                                                        value: floor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // --------------------------------------------
                                // FULL PROPERTY ADDRESS CARD
                                // --------------------------------------------
                                _staggeredEntrance(
                                  begin: 0.20,
                                  end: 0.62,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: borderCol,
                                        width: 1,
                                      ),
                                      boxShadow: cardShadow,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF3A240F)
                                                    : const Color(0xFFFFEDD5),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                Icons.location_on_rounded,
                                                color: isDark
                                                    ? const Color(0xFFFB923C)
                                                    : const Color(0xFFC2410C),
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Full Property Address',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: HomeThemeTokens.manrope(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -0.1,
                                                  color: textPri,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _InteractivePress(
                                              child: Tooltip(
                                                message: 'Copy Address',
                                                child: Material(
                                                  color: softTealCol,
                                                  borderRadius:
                                                      BorderRadius.circular(13),
                                                  child: InkWell(
                                                    onTap:
                                                        copyAddressToClipboard,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      13,
                                                    ),
                                                    child: SizedBox(
                                                      width: 42,
                                                      height: 42,
                                                      child: Icon(
                                                        Icons.copy_rounded,
                                                        color: tealCol,
                                                        size: 18,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          fullAddress,
                                          style: HomeThemeTokens.manrope(
                                            fontSize: 13.5,
                                            color: textPri,
                                            height: 1.55,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _InteractivePress(
                                          child: Material(
                                            color: isDark
                                                ? HomeThemeTokens.darkSurface
                                                : const Color(0xFFF6F9F8),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: InkWell(
                                              onTap: copyAddressToClipboard,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: borderCol.withValues(
                                                      alpha: 0.65,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .content_copy_rounded,
                                                      size: 14,
                                                      color: tealCol,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'Tap to copy full address for delivery or visitors',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: HomeThemeTokens
                                                            .manrope(
                                                          fontSize: 12,
                                                          color: tealCol,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // --------------------------------------------
                                // AMENITIES & INCLUSIONS SECTION
                                // --------------------------------------------
                                _staggeredEntrance(
                                  begin: 0.34,
                                  end: 0.78,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return Row(
                                        children: [
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  (constraints.maxWidth - 18)
                                                      .clamp(
                                                40.0,
                                                double.infinity,
                                              ),
                                            ),
                                            child: Text(
                                              'AMENITIES & INCLUSIONS',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 11.0,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.55,
                                                color: textSec,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: borderCol,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),

                                _staggeredEntrance(
                                  begin: 0.42,
                                  end: 0.92,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: borderCol,
                                        width: 1,
                                      ),
                                      boxShadow: cardShadow,
                                    ),
                                    child: amenities.isEmpty
                                        ? Center(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 12,
                                              ),
                                              child: Text(
                                                'No amenities listed for this property.',
                                                style: HomeThemeTokens.manrope(
                                                  color: textSec,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: List.generate(
                                              amenities.length,
                                              (index) {
                                                final amenity =
                                                    amenities[index];
                                                final chip = Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 13,
                                                    vertical: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isDark
                                                        ? HomeThemeTokens
                                                            .darkSurface
                                                        : const Color(
                                                            0xFFF6F9F8,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      14,
                                                    ),
                                                    border: Border.all(
                                                      color: borderCol,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        _getAmenityIcon(
                                                          amenity,
                                                        ),
                                                        size: 17.5,
                                                        color: tealCol,
                                                      ),
                                                      const SizedBox(width: 9),
                                                      Flexible(
                                                        child: Text(
                                                          amenity,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: HomeThemeTokens
                                                              .manrope(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: textPri,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                if (disableAnim) return chip;

                                                final start = (0.42 +
                                                        (index * 0.045))
                                                    .clamp(0.42, 0.85);
                                                final end = (start + 0.16)
                                                    .clamp(0.58, 1.0);
                                                final chipAnim =
                                                    CurvedAnimation(
                                                  parent: _entranceController,
                                                  curve: Interval(
                                                    start,
                                                    end,
                                                    curve: Curves.easeOutCubic,
                                                  ),
                                                );
                                                return AnimatedBuilder(
                                                  animation: chipAnim,
                                                  child: chip,
                                                  builder: (context, child) {
                                                    final t = chipAnim.value;
                                                    return Opacity(
                                                      opacity: t.clamp(
                                                        0.0,
                                                        1.0,
                                                      ),
                                                      child: Transform.scale(
                                                        scale: 0.92 +
                                                            (0.08 * t),
                                                        child: child,
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStatTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8BE3D4), size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    color: const Color(0xFFB7C6D2),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getAmenityIcon(String amenity) {
    final a = amenity.toLowerCase();
    if (a.contains('wi-fi') || a.contains('wifi') || a.contains('internet')) {
      return Icons.wifi_rounded;
    }
    if (a.contains('meal') ||
        a.contains('food') ||
        a.contains('mess') ||
        a.contains('dining')) {
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
    if (a.contains('cctv') ||
        a.contains('security') ||
        a.contains('biometric')) {
      return Icons.security_rounded;
    }
    if (a.contains('power') ||
        a.contains('backup') ||
        a.contains('electricity')) {
      return Icons.bolt_rounded;
    }
    if (a.contains('lounge') || a.contains('tv')) {
      return Icons.tv_rounded;
    }
    if (a.contains('ac') ||
        a.contains('cooler') ||
        a.contains('air condition')) {
      return Icons.ac_unit_rounded;
    }
    if (a.contains('parking') || a.contains('vehicle')) {
      return Icons.local_parking_rounded;
    }
    return Icons.check_circle_outline_rounded;
  }
}

/// Subtle architectural dot-grid backdrop inside the navy hero card.
class _HeroDotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const step = 14.0;
    for (double y = 7; y < size.height; y += step) {
      for (double x = 7; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clean vector building graphic rendered inside the Property hero card.
class _HeroBuildingGraphic extends StatelessWidget {
  final Color highlightFloorColor;

  const _HeroBuildingGraphic({required this.highlightFloorColor});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(68, 84),
      painter: _HeroBuildingPainter(highlightFloorColor: highlightFloorColor),
    );
  }
}

class _HeroBuildingPainter extends CustomPainter {
  final Color highlightFloorColor;

  const _HeroBuildingPainter({required this.highlightFloorColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 2, w - 8, h - 4),
      const Radius.circular(8),
    );
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(outerRect, outlinePaint);

    final dimFloorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.11)
      ..style = PaintingStyle.fill;

    final activeFloorPaint = Paint()
      ..color = highlightFloorColor
      ..style = PaintingStyle.fill;

    final doorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 10, w - 24, 12),
        const Radius.circular(4),
      ),
      dimFloorPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 27, w - 24, 12),
        const Radius.circular(4),
      ),
      activeFloorPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 44, w - 24, 12),
        const Radius.circular(4),
      ),
      dimFloorPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 62, 16, h - 66),
        const Radius.circular(3.5),
      ),
      doorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HeroBuildingPainter oldDelegate) =>
      oldDelegate.highlightFloorColor != highlightFloorColor;
}

/// Tactile press scale feedback wrapper respecting reduced motion.
class _InteractivePress extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _InteractivePress({
    this.onTap,
    required this.child,
  });

  @override
  State<_InteractivePress> createState() => _InteractivePressState();
}

class _InteractivePressState extends State<_InteractivePress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final scaled = AnimatedScale(
      scale: (_pressed && !disableAnim) ? 0.96 : 1.0,
      duration: disableAnim ? Duration.zero : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    if (widget.onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: scaled,
      );
    }

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: scaled,
    );
  }
}
