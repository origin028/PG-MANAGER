import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _sheenController;
  bool _animationStarted = false;

  // Live API dashboard state with instant local caching
  bool _hasApiDashboard = false;
  Map<String, dynamic> _residentInfo = {};
  Map<String, dynamic> _stayDetails = {};
  Map<String, dynamic> _rentSummary = {};
  Map<String, dynamic> _payNow = {};
  List<Map<String, dynamic>> _complaints = [];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Instant local memory initialization (stale-while-revalidate)
    _initFromCache();

    // Fetch fresh data in background without blocking UI
    _loadDashboard();
  }

  void _initFromCache() {
    final cached = TokenStorage.cachedDashboard;
    if (cached != null && cached.isNotEmpty) {
      _applyDashboardData(cached, isFromCache: true);
    } else {
      final savedProfile = TokenStorage.residentProfile;
      final source = (savedProfile != null && savedProfile.isNotEmpty)
          ? savedProfile
          : AppData.currentResident;
      if (source.isNotEmpty) {
        final profileStay = (source['stay_details'] as Map?)?.cast<String, dynamic>() ?? {};
        final profileInfo = (source['resident_info'] as Map?)?.cast<String, dynamic>() ?? {};
        _residentInfo = profileInfo.isNotEmpty ? profileInfo : source;
        _stayDetails = profileStay.isNotEmpty ? profileStay : source;
        _hasApiDashboard = true;
      }
    }

    // Initialize complaints from AppData fallback immediately
    if (AppData.complaints.isNotEmpty) {
      _complaints = List<Map<String, dynamic>>.from(AppData.complaints);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _entranceController.value = 1.0;
        _sheenController.value = 1.0;
      } else {
        _entranceController.forward();
        _sheenController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _sheenController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    // Non-blocking parallel background refresh
    await Future.wait([
      _fetchDashboardApi(),
      _fetchComplaintsApi(),
    ]);
  }

  void _applyDashboardData(Map<String, dynamic> dash, {bool isFromCache = false}) {
    final residentInfo = (dash['resident_info'] as Map?)?.cast<String, dynamic>() ?? {};
    final stay = (dash['stay_details'] as Map?)?.cast<String, dynamic>() ?? {};
    final rentSummary = (dash['rent_summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final payNow = (rentSummary['pay_now'] as Map?)?.cast<String, dynamic>() ?? {};

    final rawNotices = (dash['recent_notices'] as List?) ?? (dash['notices'] as List?) ?? [];
    final rawPayments = (dash['recent_payments'] as List?) ?? [];

    final dynamic rawDue = rentSummary['total_due'] ??
        rentSummary['outstanding_dues'] ??
        dash['rent_due'];
    final int rentDueInt = rawDue is num
        ? rawDue.toInt()
        : (int.tryParse(rawDue?.toString() ?? '') ?? 0);

    final dynamic rawMonthlyRent = stay['monthly_rent'] ??
        rentSummary['current_rent_amount'] ??
        AppData.currentResident['rent'];
    final String rentStatusStr =
        (rentSummary['rent_payment_status'] ?? rentSummary['status'] ?? '')
            .toString()
            .toUpperCase();

    final bool isPaidStatus = rentStatusStr == 'PAID' ||
        (rentStatusStr.isEmpty && rentDueInt == 0 && rawPayments.isNotEmpty);

    _hasApiDashboard = true;
    _residentInfo = residentInfo;
    _stayDetails = stay;
    _rentSummary = rentSummary;
    _payNow = payNow;

    AppData.currentResident = {
      ...AppData.currentResident,
      if (residentInfo['full_name'] != null) 'name': residentInfo['full_name'],
      if (stay['resident_name'] != null) 'name': stay['resident_name'],
      if (stay['room_number'] != null) 'room_number': stay['room_number'],
      if (stay['room_number'] != null) 'room': stay['room_number'],
      if (stay['floor_number'] != null) 'floor_number': stay['floor_number'],
      if (stay['bed_number'] != null) 'bed': stay['bed_number'],
      'rent': rawMonthlyRent,
      if (stay['living_since'] != null) 'living_since': stay['living_since'],
      if (stay['check_in_date'] != null) 'check_in_date': stay['check_in_date'],
      'rent_status': isPaidStatus ? 'Paid' : 'Unpaid',
      if (stay['property_name'] != null) 'property': stay['property_name'],
      if (residentInfo['status'] != null)
        'status': residentInfo['status']
      else if (stay['status'] != null)
        'status': stay['status'],
    };

    if (rawNotices.isNotEmpty) {
      AppData.notices = rawNotices.map((n) {
        final map = n as Map;
        final createdStr = map['created_at']?.toString() ?? '';
        return <String, dynamic>{
          'id': map['id']?.toString() ?? '',
          'title': map['title'] ?? 'Notice',
          'message': map['content'] ?? map['message'] ?? '',
          'date': createdStr.length >= 10 ? createdStr.substring(0, 10) : createdStr,
          'priority': map['is_pinned'] == true
              ? 'HIGH'
              : (map['priority'] ?? 'NORMAL'),
        };
      }).toList();
    }
  }

  Future<void> _fetchDashboardApi() async {
    try {
      final dash = await ResidentApiService.getDashboard();
      if (dash.isNotEmpty && mounted) {
        setState(() {
          _applyDashboardData(dash);
        });
        TokenStorage.saveCachedDashboard(dash);
      }
    } catch (e) {
      debugPrint('API getDashboard error: $e');
    }
  }

  Future<void> _fetchComplaintsApi() async {
    try {
      final list = await ResidentApiService.getComplaints();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _complaints = list.map((c) {
            final st = (c['status'] ?? 'PENDING').toString().toUpperCase();
            final mappedStatus = st == 'RESOLVED' || st == 'CLOSED'
                ? 'Resolved'
                : (st == 'IN_PROGRESS' ? 'In Progress' : 'Pending');
            return <String, dynamic>{
              'id': c['id']?.toString() ?? '',
              'title': c['title'] ?? c['issue'] ?? c['description'] ?? 'Maintenance Request',
              'category': c['category'] ?? 'General',
              'status': mappedStatus,
              'date': c['created_at']?.toString().substring(0, 10) ?? 'Recent',
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('API getComplaints error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Presentation Formatters & Safe Parsers
  // ---------------------------------------------------------------------------
  String _getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'R';
  }

  String _formatIndianAmount(num amount) {
    final bool hasDecimals = (amount % 1) != 0;
    final int whole = amount.truncate();
    final String wholeStr = whole.abs().toString();
    String formatted;
    if (wholeStr.length <= 3) {
      formatted = wholeStr;
    } else {
      final last3 = wholeStr.substring(wholeStr.length - 3);
      var rest = wholeStr.substring(0, wholeStr.length - 3);
      final buffer = StringBuffer();
      while (rest.length > 2) {
        buffer.write(',${rest.substring(rest.length - 2)}');
        rest = rest.substring(0, rest.length - 2);
      }
      formatted = '$rest${buffer.toString()},$last3';
    }
    final sign = amount < 0 ? '-' : '';
    if (hasDecimals) {
      final dec = (amount - whole).abs().toStringAsFixed(2).substring(1);
      return '$sign$formatted$dec';
    }
    return '$sign$formatted';
  }

  String _formatOrdinalFloor(dynamic rawFloor, String roomNumber) {
    int? floorNum;
    if (rawFloor is int) {
      floorNum = rawFloor;
    } else if (rawFloor != null) {
      floorNum = int.tryParse(rawFloor.toString());
    }
    if (floorNum == null && roomNumber.length >= 3) {
      floorNum = int.tryParse(roomNumber[0]);
    }
    floorNum ??= 1;

    if (floorNum == 0) return 'Ground';
    final mod100 = floorNum % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${floorNum}th';
    switch (floorNum % 10) {
      case 1:
        return '${floorNum}st';
      case 2:
        return '${floorNum}nd';
      case 3:
        return '${floorNum}rd';
      default:
        return '${floorNum}th';
    }
  }

  static const List<String> _monthShortNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const List<String> _monthFullNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatDateLabel(String? raw, {bool includeYear = true}) {
    if (raw == null || raw.trim().isEmpty) {
      return includeYear ? '01 Oct 2026' : '05 Nov';
    }
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) {
      return raw.trim();
    }
    final day = parsed.day.toString().padLeft(2, '0');
    final mon = _monthShortNames[parsed.month - 1];
    return includeYear ? '$day $mon ${parsed.year}' : '$day $mon';
  }

  String _formatBillingMonthTitle(String? rawMonth, DateTime? dueDate) {
    if (rawMonth != null && rawMonth.trim().isNotEmpty) {
      final clean = rawMonth.trim();
      final ymMatch = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(clean);
      if (ymMatch != null) {
        final m = int.tryParse(ymMatch.group(2)!) ?? 1;
        if (m >= 1 && m <= 12) {
          return '${_monthFullNames[m - 1]} rent';
        }
      }
      final firstWord = clean.split(' ').first;
      if (_monthFullNames.any((m) => m.toLowerCase() == firstWord.toLowerCase())) {
        return '$firstWord rent';
      }
      return clean.toLowerCase().contains('rent') ? clean : '$clean rent';
    }
    if (dueDate != null) {
      return '${_monthFullNames[dueDate.month - 1]} rent';
    }
    final now = DateTime.now();
    return '${_monthFullNames[now.month - 1]} rent';
  }

  Widget _staggeredEntrance({
    required double begin,
    required double end,
    required Widget child,
  }) {
    final curve = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.045),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Object? extra;
    try {
      extra = GoRouterState.of(context).extra;
    } catch (_) {
      extra = null;
    }

    final savedProfile = TokenStorage.residentProfile;
    final bool isDefaultPlaceholder =
        AppData.currentResident['phone'] == AppData.residents.first['phone'] &&
        AppData.currentResident['room_number'] == null &&
        (AppData.currentResident['status']?.toString().toLowerCase() == 'pending');

    Map<String, dynamic> loggedInResident = (savedProfile != null &&
            savedProfile.isNotEmpty &&
            isDefaultPlaceholder)
        ? Map<String, dynamic>.from(savedProfile)
        : <String, dynamic>{
            ...?savedProfile,
            ...AppData.currentResident,
          };
    if (extra is Map<String, dynamic>) {
      loggedInResident = {...loggedInResident, ...extra};
    } else if (extra is String && extra.trim().isNotEmpty) {
      loggedInResident = {...loggedInResident, 'name': extra};
    }

    final profileResidentInfo =
        (loggedInResident['resident_info'] as Map?)?.cast<String, dynamic>() ?? {};
    final profileStayDetails =
        (loggedInResident['stay_details'] as Map?)?.cast<String, dynamic>() ?? {};

    final name = (_residentInfo['full_name'] ??
            profileResidentInfo['full_name'] ??
            loggedInResident['full_name'] ??
            loggedInResident['name'] ??
            'Resident')
        .toString()
        .trim();
    final displayName = name.isEmpty ? 'Resident' : name;

    final rawRoom = _stayDetails['room_number'] ??
        _stayDetails['room'] ??
        profileStayDetails['room_number'] ??
        profileStayDetails['room'] ??
        loggedInResident['room_number'] ??
        loggedInResident['room'];
    final roomNumber = (rawRoom != null && rawRoom.toString().trim().isNotEmpty && rawRoom.toString().trim() != 'null')
        ? rawRoom.toString().trim()
        : '101';

    final propertyName = (_stayDetails['property_name'] ??
            profileStayDetails['property_name'] ??
            loggedInResident['property_name'] ??
            loggedInResident['property'] ??
            'BNR Luxury PG')
        .toString()
        .trim();

    final status = (_residentInfo['status'] ??
            profileResidentInfo['status'] ??
            loggedInResident['status'] ??
            'Active')
        .toString();

    final bool isPending = (rawRoom == null ||
            rawRoom.toString().trim().isEmpty ||
            rawRoom.toString().trim() == 'null') &&
        status.toLowerCase() == 'pending';

    final floor = _formatOrdinalFloor(
      _stayDetails['floor_number'] ??
          profileStayDetails['floor_number'] ??
          loggedInResident['floor_number'],
      roomNumber,
    );

    final residentSince = _formatDateLabel(
      (_stayDetails['living_since'] ??
              _stayDetails['check_in_date'] ??
              profileStayDetails['living_since'] ??
              profileStayDetails['check_in_date'] ??
              loggedInResident['living_since'] ??
              loggedInResident['check_in_date'] ??
              loggedInResident['created_at'])
          ?.toString(),
      includeYear: true,
    );

    // Rent & Invoice calculation
    final dynamic rawRent = _payNow['amount_due'] != null &&
            (_payNow['amount_due'] as num) > 0
        ? _payNow['amount_due']
        : (_rentSummary['total_due'] != null && (_rentSummary['total_due'] as num) > 0
            ? _rentSummary['total_due']
            : (_rentSummary['current_rent_amount'] ??
                profileStayDetails['monthly_rent'] ??
                loggedInResident['rent']));
    final double rentAmount = rawRent is num
        ? rawRent.toDouble()
        : (double.tryParse(rawRent?.toString() ?? '') ?? 8000.0);
    final int displayRentInt = rentAmount > 0 ? rentAmount.round() : 8000;

    final rentPaymentStatus = (_rentSummary['rent_payment_status'] ??
            _rentSummary['status'] ??
            loggedInResident['rent_status'] ??
            'DUE')
        .toString()
        .toUpperCase();

    final bool isRentPaid = !_hasApiDashboard
        ? loggedInResident['rent_status']?.toString().toLowerCase() == 'paid'
        : (rentPaymentStatus == 'PAID' ||
            (rentPaymentStatus == 'NO_INVOICE' && (_rentSummary['total_due'] ?? 1) == 0));

    final String? rawDueDateStr =
        (_rentSummary['next_due_date'] ??
         _rentSummary['rent_due_date'] ??
         loggedInResident['due_date'] ??
         loggedInResident['rent_due_date'])?.toString();
    final DateTime? parsedDueDate =
        rawDueDateStr != null ? DateTime.tryParse(rawDueDateStr) : null;

    final String billingMonthLabel = _formatBillingMonthTitle(
      _payNow['billing_month']?.toString(),
      parsedDueDate,
    );
    final String dueDateShort = parsedDueDate != null
        ? _formatDateLabel(rawDueDateStr, includeYear: false)
        : '05 Nov';

    final int? daysLeft = parsedDueDate != null
        ? parsedDueDate.difference(DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          )).inDays
        : (isPending ? null : (isRentPaid ? null : 1));

    String statusChipText;
    bool statusIsSuccess = false;
    String progLeftText;
    String progRightText;
    double progressFraction;

    if (isPending) {
      statusChipText = 'Pending';
      progLeftText = 'Awaiting room allotment';
      progRightText = 'Profile under review';
      progressFraction = 0.25;
    } else if (isRentPaid) {
      statusChipText = 'Paid';
      statusIsSuccess = true;
      progLeftText = 'All dues cleared';
      progRightText = 'Settled';
      progressFraction = 1.0;
    } else if (daysLeft != null && daysLeft < 0) {
      final overdueDays = daysLeft.abs();
      statusChipText = overdueDays == 1 ? 'Overdue 1 day' : 'Overdue ${overdueDays}d';
      progLeftText = 'Overdue by $overdueDays ${overdueDays == 1 ? 'day' : 'days'}';
      progRightText = 'Due $dueDateShort';
      progressFraction = 0.96;
    } else if (daysLeft == 0) {
      statusChipText = 'Due today';
      progLeftText = 'Due today';
      progRightText = 'Due $dueDateShort';
      progressFraction = 0.9;
    } else if (daysLeft == 1) {
      statusChipText = 'Due tomorrow';
      progLeftText = '1 day left';
      progRightText = 'Due $dueDateShort';
      progressFraction = 0.8;
    } else {
      final d = daysLeft ?? 5;
      statusChipText = 'Due in ${d}d';
      progLeftText = '$d days left';
      progRightText = 'Due $dueDateShort';
      progressFraction = (1.0 - (d.clamp(0, 30) / 30.0)).clamp(0.25, 0.85);
    }

    final String? payNowInvoiceNo = _payNow['invoice_number']?.toString();

    // Check if Rent Warning should be displayed:
    // "Show the warning exactly 2 days before the rent payment due date.
    // The warning should be displayed below the green card on the Home Screen.
    // It should automatically disappear or update when the rent is paid or the due date changes."
    final bool showRentWarning = !isRentPaid && !isPending && daysLeft != null && daysLeft <= 2;

    // Notices state
    final noticesList = AppData.notices;
    final int noticeCount = _hasApiDashboard ? noticesList.length : (noticesList.isNotEmpty ? noticesList.length : 2);
    final String noticePreview = noticesList.isNotEmpty
        ? (noticesList.first['title']?.toString() ?? 'Water maintenance tomorrow')
        : (_hasApiDashboard ? 'No new announcements' : 'Water maintenance tomorrow');

    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg = HomeThemeTokens.cardBg(context);
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              color: tealCol,
              backgroundColor: cardBg,
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ====================================================
                    // A. HEADER SECTION (Clean, without notifications bell)
                    // ====================================================
                    _staggeredEntrance(
                      begin: 0.0,
                      end: 0.45,
                      child: _buildHeader(
                        context: context,
                        displayName: displayName,
                        isDark: isDark,
                        borderCol: borderCol,
                        textPri: textPri,
                        textSec: textSec,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ====================================================
                    // B. GREEN HERO RENT SUMMARY CARD (No Pay Now/Receipt buttons)
                    // ====================================================
                    _staggeredEntrance(
                      begin: 0.08,
                      end: 0.58,
                      child: _buildHeroCard(
                        context: context,
                        isDark: isDark,
                        isPending: isPending,
                        billingMonthLabel: billingMonthLabel,
                        displayRentInt: displayRentInt,
                        rentAmount: rentAmount,
                        statusChipText: statusChipText,
                        statusIsSuccess: statusIsSuccess,
                        progLeftText: progLeftText,
                        progRightText: progRightText,
                        progressFraction: progressFraction,
                        propertyName: propertyName,
                        roomNumber: roomNumber,
                        floor: floor,
                        residentSince: residentSince,
                        payNowInvoiceNo: payNowInvoiceNo,
                        disableAnim: disableAnim,
                      ),
                    ),

                    // ====================================================
                    // C. RENT PAYMENT WARNING (Appears 2 days before due date)
                    // ====================================================
                    if (showRentWarning) ...[
                      const SizedBox(height: 14),
                      _staggeredEntrance(
                        begin: 0.14,
                        end: 0.64,
                        child: _buildRentWarningCard(
                          context: context,
                          isDark: isDark,
                          daysLeft: daysLeft,
                          dueDateShort: dueDateShort,
                          amount: displayRentInt,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ====================================================
                    // D. NOTICES SECTION
                    // ====================================================
                    _staggeredEntrance(
                      begin: 0.22,
                      end: 0.74,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Notices',
                            style: HomeThemeTokens.manrope(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: textPri,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCardSurface(
                            isDark: isDark,
                            cardBg: cardBg,
                            borderCol: borderCol,
                            child: _buildTodayRow(
                              isDark: isDark,
                              textSec: textSec,
                              iconBg: softTealCol,
                              iconColor: tealCol,
                              icon: Icons.campaign_outlined,
                              onTap: () => context.push('/notices'),
                              titleWidget: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Property Announcements',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: textPri,
                                    ),
                                  ),
                                  if (noticeCount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tealCol,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        '$noticeCount new',
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? const Color(0xFF04201C)
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: noticePreview,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ====================================================
                    // E. COMPLAINT STATUS SECTION (Replaces Today's Dinner)
                    // ====================================================
                    _staggeredEntrance(
                      begin: 0.30,
                      end: 0.84,
                      child: _buildComplaintStatusSection(
                        context: context,
                        isDark: isDark,
                        cardBg: cardBg,
                        borderCol: borderCol,
                        textPri: textPri,
                        textSec: textSec,
                        tealCol: tealCol,
                        softTealCol: softTealCol,
                      ),
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

  Widget _buildHeader({
    required BuildContext context,
    required String displayName,
    required bool isDark,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
  }) {
    final avatarBg = isDark
        ? const Color(0xFF2B5A72)
        : HomeThemeTokens.lightNavy;
    final avatarRing = isDark ? HomeThemeTokens.darkCardSurface : Colors.white;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
          ),
          child: Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarRing,
              border: Border.all(color: borderCol, width: 1),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: avatarBg,
              ),
              child: Center(
                child: Text(
                  _getInitials(displayName),
                  style: HomeThemeTokens.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome back',
                style: HomeThemeTokens.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textSec,
                ),
              ),
              Text(
                displayName,
                style: HomeThemeTokens.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: textPri,
                  letterSpacing: -0.35,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard({
    required BuildContext context,
    required bool isDark,
    required bool isPending,
    required String billingMonthLabel,
    required int displayRentInt,
    required double rentAmount,
    required String statusChipText,
    required bool statusIsSuccess,
    required String progLeftText,
    required String progRightText,
    required double progressFraction,
    required String propertyName,
    required String roomNumber,
    required String floor,
    required String residentSince,
    required String? payNowInvoiceNo,
    required bool disableAnim,
  }) {
    final statusBg = statusIsSuccess
        ? HomeThemeTokens.successBg(context)
        : HomeThemeTokens.warningBg(context);
    final statusFg = statusIsSuccess
        ? HomeThemeTokens.success(context)
        : HomeThemeTokens.warning(context);
    final dotColor = statusIsSuccess
        ? statusFg
        : (isDark ? HomeThemeTokens.darkWarning : HomeThemeTokens.lightWarningDot);

    final formattedAmount = _formatIndianAmount(
      (isPending && rentAmount <= 0) ? 0 : displayRentInt,
    );

    final Animation<double> amountPop = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.86, end: 1.04), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.0), weight: 40),
    ]).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.15, 0.72, curve: Curves.easeOutCubic),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: HomeThemeTokens.heroGradient(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x660B2231)
                : const Color(0x470B2231),
            blurRadius: 30,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Concentric teal-mint arcs & soft radial glow
            Positioned(
              right: -75,
              top: -95,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF5EEAD4).withValues(alpha: 0.14),
                      width: 1.2,
                    ),
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF42C8B4).withValues(alpha: 0.24),
                        const Color(0xFF42C8B4).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Animated glass sheen sweep on entrance
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _sheenController,
                  builder: (context, _) {
                    if (disableAnim ||
                        _sheenController.value == 0 ||
                        _sheenController.value == 1) {
                      return const SizedBox.shrink();
                    }
                    final progress = Curves.easeOut.transform(_sheenController.value);
                    return FractionalTranslation(
                      translation: Offset(-1.2 + progress * 2.4, 0),
                      child: Transform.rotate(
                        angle: -0.25,
                        child: FractionallySizedBox(
                          widthFactor: 0.35,
                          heightFactor: 1.8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: 0.11),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top row: Month & Amount + Status chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    billingMonthLabel,
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFB7C6D2),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (payNowInvoiceNo != null && payNowInvoiceNo.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '• $payNowInvoiceNo',
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF8FA7B8),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            ScaleTransition(
                              scale: amountPop,
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4, right: 3),
                                      child: Text(
                                        '₹',
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white.withValues(alpha: 0.72),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formattedAmount,
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -1.3,
                                        height: 1.0,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (statusIsSuccess)
                              Icon(Icons.check_circle_rounded, size: 13, color: statusFg)
                            else
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 6),
                            Text(
                              statusChipText,
                              style: HomeThemeTokens.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: statusFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Progress row: Days left + Due date + Progress bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          progLeftText,
                          style: HomeThemeTokens.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB7C6D2),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          progRightText,
                          style: HomeThemeTokens.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 5.5,
                      color: Colors.white.withValues(alpha: 0.14),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progressFraction),
                        duration: disableAnim
                            ? Duration.zero
                            : const Duration(milliseconds: 1100),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: value.clamp(0.0, 1.0),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.circular(6)),
                                gradient: LinearGradient(
                                  colors: [Color(0xFF2FB8A3), Color(0xFF8BE3D4)],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Property & Stay Information Footer Strip
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.push('/property-details'),
                      child: Container(
                        padding: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.16),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 12,
                              child: _buildStayMetric(
                                label: propertyName,
                                value: isPending ? 'Room Pending' : 'Room $roomNumber',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 6,
                              child: _buildStayMetric(
                                label: 'Floor',
                                value: floor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 12,
                              child: _buildStayMetric(
                                label: 'Resident since',
                                value: residentSince,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStayMetric({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: HomeThemeTokens.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFB7C6D2),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: HomeThemeTokens.manrope(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildRentWarningCard({
    required BuildContext context,
    required bool isDark,
    required int daysLeft,
    required String dueDateShort,
    required int amount,
  }) {
    String warningTitle;
    String warningSubtitle;
    Color warningBg;
    Color warningBorder;
    Color warningIconColor;

    if (daysLeft < 0) {
      final overdue = daysLeft.abs();
      warningTitle = overdue == 1
          ? 'Rent payment is 1 day overdue'
          : 'Rent payment is $overdue days overdue';
      warningSubtitle = 'Due date was $dueDateShort. Please pay promptly to avoid late charges.';
      warningBg = isDark ? const Color(0xFF381A1A) : const Color(0xFFFEF2F2);
      warningBorder = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5);
      warningIconColor = const Color(0xFFEF4444);
    } else if (daysLeft == 0) {
      warningTitle = 'Rent payment is due today';
      warningSubtitle = 'Due date is today ($dueDateShort). Clear your dues promptly.';
      warningBg = isDark ? const Color(0xFF382310) : const Color(0xFFFFFBEB);
      warningBorder = isDark ? const Color(0xFF92400E) : const Color(0xFFFCD34D);
      warningIconColor = const Color(0xFFF59E0B);
    } else if (daysLeft == 1) {
      warningTitle = 'Rent payment due tomorrow';
      warningSubtitle = 'Due date is tomorrow ($dueDateShort). Pay online to avoid dues.';
      warningBg = isDark ? const Color(0xFF382310) : const Color(0xFFFFFBEB);
      warningBorder = isDark ? const Color(0xFF92400E) : const Color(0xFFFCD34D);
      warningIconColor = const Color(0xFFF59E0B);
    } else {
      warningTitle = 'Rent payment due in 2 days';
      warningSubtitle = 'Upcoming rent payment is due on $dueDateShort.';
      warningBg = isDark ? const Color(0xFF1B2E2B) : const Color(0xFFF0FDF4);
      warningBorder = isDark ? const Color(0xFF115E59) : const Color(0xFFBBF7D0);
      warningIconColor = HomeThemeTokens.teal(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warningBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: warningIconColor.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: warningIconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_active_rounded, color: warningIconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  warningTitle,
                  style: HomeThemeTokens.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  warningSubtitle,
                  style: HomeThemeTokens.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => context.go('/payments'),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: warningIconColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Pay',
                style: HomeThemeTokens.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintStatusSection({
    required BuildContext context,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required Color tealCol,
    required Color softTealCol,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Complaint Status',
                style: HomeThemeTokens.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: textPri,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => context.push('/complaints'),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'View all',
                  style: HomeThemeTokens.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: tealCol,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCardSurface(
          isDark: isDark,
          cardBg: cardBg,
          borderCol: borderCol,
          child: _complaints.isEmpty
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/complaints'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: softTealCol,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.task_alt_rounded,
                              color: tealCol,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No open complaints',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: textPri,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Everything looks good. Tap to view complaints history.',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: textSec,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: textSec, size: 20),
                        ],
                      ),
                    ),
                  ),
                )
              : Column(
                  children: List.generate(_complaints.take(2).length, (idx) {
                    final item = _complaints[idx];
                    final String rawStatus = (item['status'] ?? 'Pending').toString();
                    final bool isResolved = rawStatus.toLowerCase() == 'resolved';
                    final bool isInProgress = rawStatus.toLowerCase().contains('progress');

                    Color statusColor;
                    Color statusBg;
                    if (isResolved) {
                      statusColor = HomeThemeTokens.success(context);
                      statusBg = HomeThemeTokens.successBg(context);
                    } else if (isInProgress) {
                      statusColor = const Color(0xFF0284C7);
                      statusBg = const Color(0xFFE0F2FE);
                    } else {
                      statusColor = const Color(0xFFD97706);
                      statusBg = const Color(0xFFFEF3C7);
                    }

                    return Column(
                      children: [
                        if (idx > 0)
                          Divider(height: 1, thickness: 1, color: borderCol),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => context.push('/complaints'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isResolved
                                          ? Icons.check_circle_outline_rounded
                                          : (isInProgress
                                              ? Icons.engineering_outlined
                                              : Icons.pending_actions_rounded),
                                      color: statusColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          item['title'] ?? item['issue'] ?? 'Maintenance Request',
                                          style: HomeThemeTokens.manrope(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: textPri,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${item['category'] ?? 'General'} • ${item['date'] ?? 'Recent'}',
                                          style: HomeThemeTokens.manrope(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: textSec,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      rawStatus,
                                      style: HomeThemeTokens.manrope(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded, color: textSec, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
        ),
      ],
    );
  }

  Widget _buildCardSurface({
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x24000000)
                : const Color(0x140E1A1F),
            blurRadius: 22,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }

  Widget _buildTodayRow({
    required bool isDark,
    required Color textSec,
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
    required Widget titleWidget,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.04),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleWidget,
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: HomeThemeTokens.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: textSec,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
