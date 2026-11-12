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
  late final AnimationController _bellController;
  bool _animationStarted = false;

  // Live API dashboard state (preserves fallback to AppData when offline/test)
  bool _hasApiDashboard = false;
  bool _hasApiFoodMenu = false;
  Map<String, dynamic> _residentInfo = {};
  Map<String, dynamic> _stayDetails = {};
  Map<String, dynamic> _rentSummary = {};
  Map<String, dynamic> _payNow = {};
  List<Map<String, dynamic>> _recentPayments = [];
  Map<String, List<Map<String, dynamic>>> _foodMenuByDay = {};
  int _unreadNotificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];

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
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _loadDashboard();
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
        _bellController.value = 1.0;
      } else {
        _entranceController.forward();
        _sheenController.forward();
        _bellController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _sheenController.dispose();
    _bellController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    await Future.wait([
      _fetchDashboardApi(),
      _fetchFoodMenuApi(),
      _fetchNotificationsApi(),
    ]);
  }

  Future<void> _fetchDashboardApi() async {
    try {
      final dash = await ResidentApiService.getDashboard();
      if (dash.isNotEmpty && mounted) {
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

        setState(() {
          _hasApiDashboard = true;
          _residentInfo = residentInfo;
          _stayDetails = stay;
          _rentSummary = rentSummary;
          _payNow = payNow;
          _recentPayments = rawPayments
              .map((p) => Map<String, dynamic>.from(p as Map))
              .take(3)
              .toList();

          AppData.currentResident = {
            ...AppData.currentResident,
            if (residentInfo['full_name'] != null) 'name': residentInfo['full_name'],
            if (stay['resident_name'] != null) 'name': stay['resident_name'],
            if (stay['room_number'] != null) 'room_number': stay['room_number'],
            if (stay['room_number'] != null) 'room': stay['room_number'],
            if (stay['floor_number'] != null) 'floor_number': stay['floor_number'],
            if (stay['bed_number'] != null) 'bed': stay['bed_number'],
            'rent': ?rawMonthlyRent,
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
          } else {
            AppData.notices = [];
          }
        });
      }
    } catch (e) {
      debugPrint('API getDashboard error: $e');
    }
  }

  Future<void> _fetchFoodMenuApi() async {
    try {
      final menu = await ResidentApiService.getWeeklyFoodMenu();
      if (menu.isNotEmpty && mounted) {
        final rawByDay = menu['menu_by_day'] as Map?;
        final rawDaysList = menu['days'] as List?;

        if (rawByDay != null && rawByDay.isNotEmpty) {
          final parsed = <String, List<Map<String, dynamic>>>{};
          rawByDay.forEach((key, val) {
            if (val is List) {
              parsed[key.toString().toUpperCase()] =
                  val.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          });
          setState(() {
            _hasApiFoodMenu = true;
            _foodMenuByDay = parsed;
          });
        } else if (rawDaysList != null && rawDaysList.isNotEmpty) {
          setState(() {
            AppData.foodMenu = rawDaysList.map((d) {
              final map = d as Map;
              return <String, dynamic>{
                'day': map['day_of_week'] ?? 'Monday',
                'breakfast': map['breakfast'] ?? '',
                'lunch': map['lunch'] ?? '',
                'dinner': map['dinner'] ?? '',
              };
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('API getWeeklyFoodMenu error: $e');
    }
  }

  Future<void> _fetchNotificationsApi() async {
    try {
      final results = await Future.wait([
        ResidentApiService.getUnreadNotificationCount(),
        ResidentApiService.getNotifications(),
      ]);
      if (!mounted) return;
      final count = results[0] as int;
      final list = results[1] as List<Map<String, dynamic>>;
      setState(() {
        _unreadNotificationCount = count;
        _notifications = list;
      });
    } catch (e) {
      debugPrint('API getNotifications error: $e');
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
      // Check YYYY-MM format
      final ymMatch = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(clean);
      if (ymMatch != null) {
        final m = int.tryParse(ymMatch.group(2)!) ?? 1;
        if (m >= 1 && m <= 12) {
          return '${_monthFullNames[m - 1]} rent';
        }
      }
      // If e.g. "November 2026" -> "November rent"
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

  ({String mealTitle, String dishes, String? timing}) _resolveTodayFood() {
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    final weekdayIndex = DateTime.now().weekday - 1; // 0..6
    final todayTitle = dayNames[weekdayIndex];
    final todayKey = todayTitle.toUpperCase();
    final hour = DateTime.now().hour;

    String desiredMealType = 'LUNCH';
    String fallbackHeading = "Today's lunch";
    if (hour < 11) {
      desiredMealType = 'BREAKFAST';
      fallbackHeading = "Today's breakfast";
    } else if (hour >= 17) {
      desiredMealType = 'DINNER';
      fallbackHeading = "Today's dinner";
    }

    if (_hasApiFoodMenu && _foodMenuByDay.isNotEmpty) {
      final todayItems = _foodMenuByDay[todayKey] ?? [];
      if (todayItems.isNotEmpty) {
        final match = todayItems.firstWhere(
          (m) => m['meal_type']?.toString().toUpperCase() == desiredMealType,
          orElse: () => todayItems.first,
        );
        final rawType = (match['meal_type']?.toString() ?? desiredMealType).toLowerCase();
        final title = "Today's $rawType";
        final dishesList = (match['dishes'] as List?)
                ?.map((d) => d.toString().trim())
                .where((d) => d.isNotEmpty)
                .toList() ??
            [];
        final start = match['start_time']?.toString().trim() ?? '';
        final end = match['end_time']?.toString().trim() ?? '';
        final timing = (start.isNotEmpty && end.isNotEmpty)
            ? '$start – $end'
            : (start.isNotEmpty ? start : null);
        return (
          mealTitle: title,
          dishes: dishesList.isNotEmpty ? dishesList.join(', ') : 'View weekly meal schedule',
          timing: timing,
        );
      }
    }

    // Fallback to AppData.foodMenu (also populated on FoodMenuScreen or local storage)
    final menuRow = AppData.foodMenu.firstWhere(
      (d) => d['day']?.toString().toLowerCase() == todayTitle.toLowerCase(),
      orElse: () => AppData.foodMenu.isNotEmpty ? AppData.foodMenu.first : <String, dynamic>{},
    );

    if (menuRow.isNotEmpty) {
      final slotKey = desiredMealType.toLowerCase();
      String dishes = (menuRow[slotKey] ?? '').toString().trim();
      String chosenHeading = fallbackHeading;
      if (dishes.isEmpty) {
        for (final alt in ['lunch', 'breakfast', 'dinner']) {
          final val = (menuRow[alt] ?? '').toString().trim();
          if (val.isNotEmpty) {
            dishes = val;
            chosenHeading = "Today's $alt";
            break;
          }
        }
      }
      return (
        mealTitle: chosenHeading,
        dishes: dishes.isNotEmpty ? dishes : 'Tap to check weekly food menu',
        timing: null,
      );
    }

    return (
      mealTitle: fallbackHeading,
      dishes: 'Tap to check weekly food menu',
      timing: null,
    );
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

    // Extract nested resident_info / stay_details when coming from /resident/profile
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
        profileStayDetails['room_number'] ??
        loggedInResident['room_number'] ??
        loggedInResident['room'];
    final roomNumber = (rawRoom != null && rawRoom.toString().trim().isNotEmpty)
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

    final bool isPending = rawRoom == null ||
        rawRoom.toString().trim().isEmpty ||
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
              loggedInResident['check_in_date'])
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
            (rentPaymentStatus == 'NO_INVOICE' && _recentPayments.isNotEmpty));

    final String? rawDueDateStr =
        (_rentSummary['next_due_date'] ?? _rentSummary['rent_due_date'])?.toString();
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
        : (isPending ? null : 1);

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

    final String? payNowInvoiceId = _payNow['invoice_id']?.toString();
    final String? payNowInvoiceNo = _payNow['invoice_number']?.toString();

    // Notices state
    final noticesList = AppData.notices;
    final int noticeCount = _hasApiDashboard ? noticesList.length : (noticesList.isNotEmpty ? noticesList.length : 2);
    final String noticePreview = noticesList.isNotEmpty
        ? (noticesList.first['title']?.toString() ?? 'Water maintenance tomorrow')
        : (_hasApiDashboard ? 'No new announcements' : 'Water maintenance tomorrow');

    // Today's food state
    final todayFood = _resolveTodayFood();

    // Recent payments state
    final List<Map<String, dynamic>> displayPayments = _hasApiDashboard
        ? _recentPayments
        : (isPending
            ? []
            : [
                {
                  'title': 'October rent',
                  'subtitle': '01 Oct · Google Pay',
                  'amount': displayRentInt,
                  'status': 'SUCCESS',
                  'invoiceId': 'INV-2026-009',
                  'month': 'October 2026',
                },
                {
                  'title': 'September rent',
                  'subtitle': '01 Sep · PhonePe',
                  'amount': displayRentInt,
                  'status': 'SUCCESS',
                  'invoiceId': 'INV-2026-008',
                  'month': 'September 2026',
                },
              ]);

    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg = HomeThemeTokens.cardBg(context);
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final int bellBadgeCount = _unreadNotificationCount > 0
        ? _unreadNotificationCount
        : (!isRentPaid && !isPending ? 1 : 0);

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
                        // A. HEADER SECTION
                        // ====================================================
                        _staggeredEntrance(
                          begin: 0.0,
                          end: 0.45,
                          child: _buildHeader(
                            context: context,
                            displayName: displayName,
                            isDark: isDark,
                            cardBg: cardBg,
                            borderCol: borderCol,
                            textPri: textPri,
                            textSec: textSec,
                            showBellDot: bellBadgeCount > 0,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ====================================================
                        // B & C. HERO RENT + STAY INFORMATION CARD
                        // ====================================================
                        _staggeredEntrance(
                          begin: 0.08,
                          end: 0.58,
                          child: _buildHeroCard(
                            context: context,
                            isDark: isDark,
                            isPending: isPending,
                            isRentPaid: isRentPaid,
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
                            payNowInvoiceId: payNowInvoiceId,
                            payNowInvoiceNo: payNowInvoiceNo,
                            dueDateShort: dueDateShort,
                            disableAnim: disableAnim,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ====================================================
                        // D & E. TODAY SECTION (NOTICES + TODAY'S FOOD)
                        // ====================================================
                        _staggeredEntrance(
                          begin: 0.22,
                          end: 0.74,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Today',
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
                                child: Column(
                                  children: [
                                    // Row 1: Notices
                                    _staggeredEntrance(
                                      begin: 0.30,
                                      end: 0.80,
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
                                              'Notices',
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
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: borderCol,
                                    ),
                                    // Row 2: Today's Food
                                    _staggeredEntrance(
                                      begin: 0.38,
                                      end: 0.88,
                                      child: _buildTodayRow(
                                        isDark: isDark,
                                        textSec: textSec,
                                        iconBg: HomeThemeTokens.foodBg(context),
                                        iconColor: HomeThemeTokens.foodIcon(context),
                                        icon: Icons.restaurant_rounded,
                                        onTap: () => context.go('/food-menu'),
                                        titleWidget: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                todayFood.mealTitle,
                                                style: HomeThemeTokens.manrope(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: textPri,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (todayFood.timing != null) ...[
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  todayFood.timing!,
                                                  style: HomeThemeTokens.manrope(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: textSec,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        subtitle: todayFood.dishes,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ====================================================
                        // F. RECENT PAYMENTS SECTION
                        // ====================================================
                        _staggeredEntrance(
                          begin: 0.42,
                          end: 0.96,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Recent payments',
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
                                  const SizedBox(width: 8),
                                  _ScaleTap(
                                    onTap: () => context.go('/payments'),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        'See all',
                                        style: HomeThemeTokens.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: tealCol,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildRecentPaymentsCard(
                                context: context,
                                isDark: isDark,
                                cardBg: cardBg,
                                borderCol: borderCol,
                                textPri: textPri,
                                textSec: textSec,
                                payments: displayPayments,
                                isPending: isPending,
                              ),
                            ],
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
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required bool showBellDot,
  }) {
    final avatarBg = isDark
        ? const Color(0xFF2B5A72)
        : HomeThemeTokens.lightNavy;
    final avatarRing = isDark ? HomeThemeTokens.darkCardSurface : Colors.white;
    final bellDotColor = isDark
        ? HomeThemeTokens.darkBellDot
        : HomeThemeTokens.lightBellDot;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
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
          ),
        ),
        const SizedBox(width: 12),
        _ScaleTap(
          onTap: () => _showNotificationsModal(context),
          child: Semantics(
            button: true,
            label: 'Notifications',
            child: Tooltip(
              message: 'Notifications',
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? HomeThemeTokens.darkCardSurface : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderCol, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? const Color(0x1F000000)
                          : const Color(0x080E1A1F),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _bellController,
                      builder: (context, child) {
                        double angle = 0;
                        if (showBellDot && _bellController.isAnimating) {
                          final t = _bellController.value;
                          if (t < 0.25) {
                            angle = 0.22 * (t / 0.25);
                          } else if (t < 0.50) {
                            angle = 0.22 - 0.40 * ((t - 0.25) / 0.25);
                          } else if (t < 0.75) {
                            angle = -0.18 + 0.30 * ((t - 0.50) / 0.25);
                          } else {
                            angle = 0.12 * (1.0 - (t - 0.75) / 0.25);
                          }
                        }
                        return Transform.rotate(
                          angle: angle,
                          alignment: const Alignment(0, -0.6),
                          child: child,
                        );
                      },
                      child: Icon(
                        Icons.notifications_none_rounded,
                        color: textPri,
                        size: 22,
                      ),
                    ),
                    if (showBellDot)
                      Positioned(
                        top: 9,
                        right: 10,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: bellDotColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? HomeThemeTokens.darkCardSurface
                                  : Colors.white,
                              width: 1.8,
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
      ],
    );
  }

  Widget _buildHeroCard({
    required BuildContext context,
    required bool isDark,
    required bool isPending,
    required bool isRentPaid,
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
    required String? payNowInvoiceId,
    required String? payNowInvoiceNo,
    required String dueDateShort,
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
    final btnTextColor = HomeThemeTokens.lightNavy;

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
            // Concentric teal-mint arcs & soft radial glow matching reference image
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
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5EEAD4).withValues(alpha: 0.045),
                        spreadRadius: 32,
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: const Color(0xFF5EEAD4).withValues(alpha: 0.03),
                        spreadRadius: 64,
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Animated diagonal glass sheen sweep on entrance
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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
                                  boxShadow: [
                                    BoxShadow(
                                      color: dotColor.withValues(alpha: 0.35),
                                      spreadRadius: 2.5,
                                      blurRadius: 0,
                                    ),
                                  ],
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
                  const SizedBox(height: 11),

                  // Progress row: Days left + Due date + Animated progress bar
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
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF2FB8A3), Color(0xFF8BE3D4)],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),

                  // Primary CTA Button: Always shows Pay now when unpaid (preserves existing flow)
                  _ScaleTap(
                    onTap: () {
                      if (isRentPaid) {
                        context.push('/receipt', extra: {
                          'invoiceId': payNowInvoiceNo ?? payNowInvoiceId ?? 'INV-2026-010',
                          'amount': rentAmount > 0 ? rentAmount : 8000,
                          'month': billingMonthLabel.replaceAll(' rent', ''),
                        });
                      } else if (payNowInvoiceId != null && payNowInvoiceId.isNotEmpty) {
                        context.push('/rent-payment', extra: {
                          'id': payNowInvoiceId,
                          'invoice_number': payNowInvoiceNo ?? '',
                          'amount': rentAmount,
                          'date': dueDateShort,
                          'month': _payNow['billing_month']?.toString() ?? 'November 2026',
                          'autoOpen': true,
                        }).then((_) => _loadDashboard());
                      } else {
                        context.go('/payments');
                      }
                    },
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: isRentPaid
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: isRentPaid
                            ? Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1,
                              )
                            : null,
                        boxShadow: isRentPaid
                            ? null
                            : const [
                                BoxShadow(
                                  color: Color(0x52000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Center(
                        child: Text(
                          isRentPaid ? 'View receipt' : 'Pay now',
                          style: HomeThemeTokens.manrope(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: isRentPaid ? Colors.white : btnTextColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),

                  // Property & Stay Information Footer Strip (matching HTML template)
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
                                value: isPending ? '—' : floor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 12,
                              child: _buildStayMetric(
                                label: 'Resident since',
                                value: isPending ? 'Under review' : residentSince,
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

  Widget _buildRecentPaymentsCard({
    required BuildContext context,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required List<Map<String, dynamic>> payments,
    required bool isPending,
  }) {
    if (payments.isEmpty) {
      return _buildCardSurface(
        isDark: isDark,
        cardBg: cardBg,
        borderCol: borderCol,
        child: InkWell(
          onTap: () => context.go('/payments'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: HomeThemeTokens.softTeal(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: HomeThemeTokens.teal(context),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No payments recorded yet',
                        style: HomeThemeTokens.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPending
                            ? 'Rent invoices will appear after room allotment'
                            : 'Tap to view invoices and payment options',
                        style: HomeThemeTokens.manrope(
                          fontSize: 13,
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
      );
    }

    return _buildCardSurface(
      isDark: isDark,
      cardBg: cardBg,
      borderCol: borderCol,
      child: Column(
        children: List.generate(payments.length, (idx) {
          final p = payments[idx];
          final String statusRaw = (p['status'] ?? 'SUCCESS').toString().toUpperCase();
          final bool isSuccess = statusRaw == 'SUCCESS' || statusRaw == 'PAID';

          // Format API or fallback fields uniformly
          String title;
          String subtitle;
          if (p.containsKey('title') && p.containsKey('subtitle')) {
            title = p['title'].toString();
            subtitle = p['subtitle'].toString();
          } else {
            final paidAt = (p['paid_at'] ?? p['payment_date'])?.toString();
            final parsedDt = paidAt != null ? DateTime.tryParse(paidAt) : null;
            final dateStr = _formatDateLabel(paidAt, includeYear: false);
            final monthName = parsedDt != null
                ? '${_monthFullNames[parsedDt.month - 1]} rent'
                : 'Rent payment';
            final methodRaw = (p['payment_method'] ?? p['payment_mode'] ?? 'UPI')
                .toString()
                .replaceAll('_', ' ');
            title = monthName;
            subtitle = isSuccess ? '$dateStr · $methodRaw' : '$dateStr · $statusRaw';
          }

          final dynamic amtRaw = p['amount'] ?? 0;
          final num amtNum = amtRaw is num
              ? amtRaw
              : (num.tryParse(amtRaw.toString()) ?? 0);

          final String? receiptNumber = p['receipt_number']?.toString();
          final String? invoiceId = (p['invoiceId'] ?? p['payment_id'] ?? receiptNumber)?.toString();
          final String? txnRef = p['transaction_reference']?.toString();
          final String monthLabel = p['month']?.toString() ?? title.replaceAll(' rent', '');

          final iconBg = isSuccess
              ? HomeThemeTokens.successBg(context)
              : HomeThemeTokens.warningBg(context);
          final iconFg = isSuccess
              ? HomeThemeTokens.success(context)
              : HomeThemeTokens.warning(context);

          return _staggeredEntrance(
            begin: (0.48 + idx * 0.07).clamp(0.0, 0.85),
            end: (0.86 + idx * 0.05).clamp(0.0, 1.0),
            child: Column(
              children: [
                if (idx > 0) Divider(height: 1, thickness: 1, color: borderCol),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isSuccess ? Icons.check_rounded : Icons.schedule_rounded,
                          color: iconFg,
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
                              title,
                              style: HomeThemeTokens.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPri,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: HomeThemeTokens.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textSec,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '₹${_formatIndianAmount(amtNum)}',
                        style: HomeThemeTokens.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPri,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ScaleTap(
                        onTap: () {
                          context.push('/receipt', extra: {
                            if (receiptNumber != null && receiptNumber.isNotEmpty)
                              'receiptId': receiptNumber,
                            'invoiceId': invoiceId ?? 'INV-2026-010',
                            'amount': amtNum,
                            'month': monthLabel,
                            'transactionRef': ?txnRef,
                          });
                        },
                        child: Semantics(
                          button: true,
                          label: 'Download receipt',
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: HomeThemeTokens.controlBg(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.receipt_long_outlined,
                              color: textPri,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _showNotificationsModal(BuildContext context) {
    final isDark = HomeThemeTokens.isDark(context);
    final modalBg = HomeThemeTokens.cardBg(context);
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);

    final bool isPaid = AppData.currentResident['rent_status']?.toString().toLowerCase() == 'paid';
    final dynamic rentAmt = AppData.currentResident['rent'] ?? 8000;
    final String? payNowInvId = _payNow['invoice_id']?.toString();
    final String? payNowInvNo = _payNow['invoice_number']?.toString();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: modalBg,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
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
                    Icon(Icons.notifications_active_rounded, color: tealCol, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: HomeThemeTokens.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textPri,
                        ),
                      ),
                    ),
                    if (_notifications.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          ResidentApiService.markAllNotificationsRead().catchError((_) {});
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          'Mark all read',
                          style: HomeThemeTokens.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tealCol,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF202A32) : HomeThemeTokens.lightBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: isPaid
                                  ? HomeThemeTokens.successBg(context)
                                  : HomeThemeTokens.warningBg(context),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.payment_rounded,
                              color: isPaid
                                  ? HomeThemeTokens.success(context)
                                  : HomeThemeTokens.warning(context),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rent Due Reminder',
                                  style: HomeThemeTokens.manrope(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: textPri,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Invoice: ${payNowInvNo ?? 'INV-2026-010'} • Due 05 Nov 2026',
                                  style: HomeThemeTokens.manrope(
                                    fontSize: 12,
                                    color: textSec,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '2h ago',
                            style: HomeThemeTokens.manrope(fontSize: 11, color: textSec),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Amount: ',
                                  style: HomeThemeTokens.manrope(fontSize: 12, color: textSec),
                                ),
                                Flexible(
                                  child: Text(
                                    '₹$rentAmt',
                                    style: HomeThemeTokens.manrope(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: textPri,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isPaid)
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push('/receipt', extra: {
                                  'invoiceId': payNowInvNo ?? 'INV-2026-010',
                                  'amount': rentAmt,
                                  'month': 'November 2026',
                                });
                              },
                              icon: Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: HomeThemeTokens.success(context),
                              ),
                              label: Text(
                                'Paid (Receipt)',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: HomeThemeTokens.success(context),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                side: BorderSide(color: HomeThemeTokens.success(context)),
                                backgroundColor: HomeThemeTokens.successBg(context),
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push('/rent-payment', extra: {
                                  'id': (payNowInvId != null && payNowInvId.isNotEmpty)
                                      ? payNowInvId
                                      : 'INV-2026-010',
                                  'invoice_number': ?payNowInvNo,
                                  'amount': rentAmt,
                                  'date': '05 Nov 2026',
                                  'month': _payNow['billing_month']?.toString() ?? 'November 2026',
                                  'autoOpen': true,
                                });
                              },
                              icon: const Icon(Icons.flash_on_rounded, size: 14),
                              label: Text(
                                'Pay Now',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tealCol,
                                foregroundColor: isDark ? const Color(0xFF04201C) : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_notifications.isNotEmpty)
                  ..._notifications.take(3).map((n) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: softTealCol,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.notifications_rounded, color: tealCol, size: 20),
                      ),
                      title: Text(
                        (n['title'] ?? 'Update').toString(),
                        style: HomeThemeTokens.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: textPri,
                        ),
                      ),
                      subtitle: Text(
                        (n['body'] ?? n['message'] ?? '').toString(),
                        style: HomeThemeTokens.manrope(fontSize: 12, color: textSec),
                      ),
                    );
                  })
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: softTealCol,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.verified_rounded, color: tealCol, size: 20),
                    ),
                    title: Text(
                      'KYC Document status',
                      style: HomeThemeTokens.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textPri,
                      ),
                    ),
                    subtitle: Text(
                      'Your profile documents are logged with property admin.',
                      style: HomeThemeTokens.manrope(fontSize: 12, color: textSec),
                    ),
                    trailing: Text(
                      '1d ago',
                      style: HomeThemeTokens.manrope(fontSize: 11, color: textSec),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight tactile scale press wrapper respecting reduced motion preferences.
class _ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _ScaleTap({
    required this.child,
    required this.onTap,
  });

  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: (_pressed && !disableAnim) ? 0.97 : 1.0,
        duration: disableAnim ? Duration.zero : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
