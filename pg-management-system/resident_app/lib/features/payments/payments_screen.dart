import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with TickerProviderStateMixin {
  late final List<Map<String, dynamic>> _invoices;
  late final AnimationController _entranceController;
  late final AnimationController _dotPulseController;
  late final AnimationController _sheenController;
  bool _animationStarted = false;
  bool _isRefreshing = false;
  String? _apiErrorMessage;

  static const List<String> _monthShortUpper = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  static const List<String> _monthShortTitle = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _monthFullNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _dotPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    final stay =
        (AppData.currentResident['stay_details'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rent = stay['monthly_rent'] ?? AppData.currentResident['rent'] ?? 8000;
    final double rentAmount = rent is num
        ? rent.toDouble()
        : (double.tryParse(rent.toString()) ?? 8000.0);
    final isRentPaid =
        AppData.currentResident['rent_status']?.toString().toLowerCase() ==
            'paid';

    _invoices = [
      {
        'id': 'INV-2026-010',
        'month': 'November 2026',
        'amount': rentAmount,
        'status': isRentPaid ? 'Paid' : 'Pending',
        'date': '05 Nov 2026',
        'invoice_type': 'RENT',
      },
      {
        'id': 'INV-2026-009',
        'month': 'October 2026',
        'amount': rentAmount > 0 ? rentAmount : 8000.0,
        'status': 'Paid',
        'date': '05 Oct 2026',
        'invoice_type': 'RENT',
      },
      {
        'id': 'INV-2026-008',
        'month': 'September 2026',
        'amount': rentAmount > 0 ? rentAmount : 8000.0,
        'status': 'Paid',
        'date': '05 Sep 2026',
        'invoice_type': 'RENT',
      },
    ];
    _loadInvoicesFromApi();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _entranceController.value = 1.0;
        _dotPulseController.value = 1.0;
        _sheenController.value = 1.0;
      } else {
        _entranceController.forward();
        _dotPulseController.forward();
        _sheenController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _dotPulseController.dispose();
    _sheenController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoicesFromApi({bool userInitiated = false}) async {
    if (userInitiated && mounted) {
      setState(() {
        _isRefreshing = true;
        _apiErrorMessage = null;
      });
    }
    try {
      final invs = await ResidentApiService.getInvoices();
      if (invs.isNotEmpty && mounted) {
        setState(() {
          _invoices.clear();
          _apiErrorMessage = null;
          for (final inv in invs) {
            final rawStatus = (inv['status'] ?? '').toString().toUpperCase();
            final mappedStatus = rawStatus == 'PAID'
                ? 'Paid'
                : (rawStatus == 'PARTIAL'
                    ? 'Partial'
                    : (rawStatus == 'FAILED' ? 'Failed' : 'Pending'));

            final rawTotal = inv['amount'];
            final num totalAmt = rawTotal is num
                ? rawTotal
                : (num.tryParse(rawTotal?.toString() ?? '') ?? 0);

            final rawBal = inv['balance_amount'];
            final num balanceAmt = rawBal is num
                ? rawBal
                : (num.tryParse(rawBal?.toString() ?? '') ?? totalAmt);

            final rawPaid = inv['paid_amount'];
            final num paidAmt = rawPaid is num
                ? rawPaid
                : (num.tryParse(rawPaid?.toString() ?? '') ?? 0);

            // For settled invoices show settled amount; for pending/partial show balance due.
            final double displayAmount = mappedStatus == 'Paid'
                ? (paidAmt > 0 ? paidAmt.toDouble() : totalAmt.toDouble())
                : (balanceAmt > 0 ? balanceAmt.toDouble() : totalAmt.toDouble());

            _invoices.add({
              'id': inv['id']?.toString() ?? '',
              'invoice_number': inv['invoice_number']?.toString() ?? '',
              'invoice_type': inv['invoice_type']?.toString() ?? 'RENT',
              'notes': inv['notes']?.toString() ?? '',
              'month': _formatMonthLabel(
                inv['billing_month']?.toString(),
                inv['due_date']?.toString(),
              ),
              'amount': displayAmount,
              'balance_amount': balanceAmt.toDouble(),
              'total_amount': totalAmt.toDouble(),
              'paid_amount': paidAmt.toDouble(),
              'status': mappedStatus,
              'date': _formatDateDisplay(inv['due_date']?.toString()),
            });
          }
        });
      }
    } catch (e) {
      debugPrint('API resident getInvoices error: $e');
      if (userInitiated && mounted) {
        setState(() {
          _apiErrorMessage = 'Could not refresh latest invoices.';
        });
      }
    } finally {
      if (mounted && _isRefreshing) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String _formatAmount(dynamic amt) {
    if (amt == null) return '0.00';
    final num val = amt is num ? amt : (num.tryParse(amt.toString()) ?? 0);
    if (val % 1 == 0 && val >= 100) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(2);
  }

  String _formatIndianAmount(dynamic amt) {
    final normalized = _formatAmount(amt);
    final num val = amt is num ? amt : (num.tryParse(amt?.toString() ?? '') ?? 0);
    final bool hasDecimals = (val % 1) != 0;
    final int whole = val.truncate();
    final String wholeStr = whole.abs().toString();
    String formatted;
    if (wholeStr.length <= 3) {
      formatted = wholeStr;
    } else {
      final last3 = wholeStr.substring(wholeStr.length - 3);
      var rest = wholeStr.substring(0, wholeStr.length - 3);
      final chunks = <String>[];
      while (rest.length > 2) {
        chunks.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) {
        chunks.insert(0, rest);
      }
      formatted = '${chunks.join(',')},$last3';
    }
    final sign = val < 0 ? '-' : '';
    if (hasDecimals && normalized.contains('.')) {
      final dec = normalized.substring(normalized.indexOf('.'));
      return '$sign$formatted$dec';
    }
    return '$sign$formatted';
  }

  String _formatMonthLabel(String? rawMonth, String? rawDueDate) {
    if (rawMonth != null && rawMonth.trim().isNotEmpty) {
      final clean = rawMonth.trim();
      final ymMatch = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(clean);
      if (ymMatch != null) {
        final year = ymMatch.group(1)!;
        final month = int.tryParse(ymMatch.group(2)!) ?? 1;
        if (month >= 1 && month <= 12) {
          return '${_monthFullNames[month - 1]} $year';
        }
      }
      return clean;
    }
    if (rawDueDate != null && rawDueDate.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawDueDate.trim());
      if (parsed != null) {
        return '${_monthFullNames[parsed.month - 1]} ${parsed.year}';
      }
    }
    return 'Current Month';
  }

  String _formatDateDisplay(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) {
      return '05 Nov 2026';
    }
    final clean = rawDate.trim();
    final parsed = DateTime.tryParse(clean);
    if (parsed != null) {
      final day = parsed.day.toString().padLeft(2, '0');
      final mon = _monthShortTitle[parsed.month - 1];
      return '$day $mon ${parsed.year}';
    }
    return clean;
  }

  ({String monthAbbr, String day}) _parseDateBadge(
    String? rawDate,
    String? rawMonth,
  ) {
    if (rawDate != null && rawDate.trim().isNotEmpty) {
      final clean = rawDate.trim();
      final iso = DateTime.tryParse(clean);
      if (iso != null) {
        return (
          monthAbbr: _monthShortUpper[iso.month - 1],
          day: iso.day.toString().padLeft(2, '0'),
        );
      }
      final humanMatch =
          RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})').firstMatch(clean);
      if (humanMatch != null) {
        return (
          monthAbbr: humanMatch.group(2)!.toUpperCase(),
          day: humanMatch.group(1)!.padLeft(2, '0'),
        );
      }
    }
    if (rawMonth != null && rawMonth.trim().length >= 3) {
      final m = rawMonth.trim().substring(0, 3).toUpperCase();
      return (monthAbbr: m, day: '05');
    }
    return (monthAbbr: 'DUE', day: '--');
  }

  String _resolvePropertySubtitle() {
    final stay =
        (AppData.currentResident['stay_details'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final property = (stay['property_name'] ??
            AppData.currentResident['property'] ??
            AppData.currentResident['pg_name'] ??
            'BNR Luxury PG')
        .toString()
        .trim();
    final rawRoom = (stay['room_number'] ??
            AppData.currentResident['room_number'] ??
            AppData.currentResident['room'] ??
            '')
        .toString()
        .trim();

    if (rawRoom.isEmpty || rawRoom == 'null') {
      return property.isNotEmpty ? property : 'Origin PG';
    }
    final roomLabel =
        rawRoom.toLowerCase().startsWith('room') ? rawRoom : 'Room $rawRoom';
    return property.isNotEmpty ? '$property · $roomLabel' : roomLabel;
  }

  void _openRentPayment(BuildContext context, Map<String, dynamic> invoice) {
    context.push('/rent-payment', extra: {...invoice, 'autoOpen': true}).then((_) {
      _loadInvoicesFromApi();
      if (!mounted) return;
      setState(() {
        final isRentPaid =
            AppData.currentResident['rent_status']?.toString().toLowerCase() ==
                'paid';
        if (isRentPaid && _invoices.isNotEmpty) {
          final idx = _invoices.indexWhere((i) => i['id'] == invoice['id']);
          if (idx != -1) {
            _invoices[idx]['status'] = 'Paid';
          }
        }
      });
    });
  }

  void _openReceipt(BuildContext context, Map<String, dynamic> invoice) {
    context.push(
      '/receipt',
      extra: {
        'invoiceId': (invoice['invoice_number'] != null &&
                invoice['invoice_number'].toString().isNotEmpty)
            ? invoice['invoice_number']
            : invoice['id'],
        'amount': invoice['amount'],
        'month': invoice['month'],
      },
    );
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
        begin.clamp(0.0, 0.99),
        end.clamp(0.01, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, inner) {
        final t = anim.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: inner,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasActionablePending = _invoices.any(
      (inv) =>
          inv['status'] == 'Pending' ||
          inv['status'] == 'Partial' ||
          inv['status'] == 'Failed',
    );
    final Map<String, dynamic> pendingInvoice = hasActionablePending
        ? _invoices.firstWhere(
            (inv) =>
                inv['status'] == 'Pending' ||
                inv['status'] == 'Partial' ||
                inv['status'] == 'Failed',
          )
        : (_invoices.isNotEmpty
            ? _invoices.first
            : <String, dynamic>{
                'amount': 0.0,
                'status': 'Paid',
                'date': '-',
                'month': 'Current Month',
              });
    final bool isPending = pendingInvoice['status'] == 'Pending' ||
        pendingInvoice['status'] == 'Partial' ||
        pendingInvoice['status'] == 'Failed';

    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final propertySubtitle = _resolvePropertySubtitle();

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: tealCol,
          backgroundColor: cardBg,
          onRefresh: () => _loadInvoicesFromApi(userInitiated: true),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ----------------------------------------------------------
                    // 1. HEADER
                    // ----------------------------------------------------------
                    _staggeredEntrance(
                      begin: 0.0,
                      end: 0.36,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            propertySubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HomeThemeTokens.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textSec,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Rent & Payments',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: HomeThemeTokens.manrope(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: textPri,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_apiErrorMessage != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: HomeThemeTokens.warningBg(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: HomeThemeTokens.warning(context)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: HomeThemeTokens.warning(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _apiErrorMessage!,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: HomeThemeTokens.warning(context),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  _loadInvoicesFromApi(userInitiated: true),
                              child: Text(
                                'Retry',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: tealCol,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ----------------------------------------------------------
                    // 2. CURRENT CYCLE HERO SUMMARY CARD
                    // ----------------------------------------------------------
                    _staggeredEntrance(
                      begin: 0.08,
                      end: 0.48,
                      child: _buildCurrentCycleCard(
                        context: context,
                        isDark: isDark,
                        cardBg: cardBg,
                        borderCol: borderCol,
                        textPri: textPri,
                        textSec: textSec,
                        tealCol: tealCol,
                        softTealCol: softTealCol,
                        isPending: isPending,
                        pendingInvoice: pendingInvoice,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ----------------------------------------------------------
                    // 3. SECTION HEADING
                    // ----------------------------------------------------------
                    _staggeredEntrance(
                      begin: 0.16,
                      end: 0.56,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Payment history & invoices',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HomeThemeTokens.manrope(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: textPri,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (_isRefreshing)
                            SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tealCol,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ----------------------------------------------------------
                    // 4. INVOICES LIST OR EMPTY STATE
                    // ----------------------------------------------------------
                    if (_invoices.isEmpty)
                      _staggeredEntrance(
                        begin: 0.24,
                        end: 0.70,
                        child: _buildEmptyState(
                          context: context,
                          cardBg: cardBg,
                          borderCol: borderCol,
                          textPri: textPri,
                          textSec: textSec,
                          tealCol: tealCol,
                          softTealCol: softTealCol,
                        ),
                      )
                    else
                      ..._invoices.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final invoice = entry.value;
                        final double start =
                            (0.24 + idx * 0.09).clamp(0.24, 0.72);
                        final double finish = (start + 0.36).clamp(0.45, 1.0);
                        return _staggeredEntrance(
                          begin: start,
                          end: finish,
                          child: _buildInvoiceCard(
                            context: context,
                            invoice: invoice,
                            isDark: isDark,
                            cardBg: cardBg,
                            borderCol: borderCol,
                            textPri: textPri,
                            textSec: textSec,
                            tealCol: tealCol,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentCycleCard({
    required BuildContext context,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required Color tealCol,
    required Color softTealCol,
    required bool isPending,
    required Map<String, dynamic> pendingInvoice,
  }) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final String amountText =
        isPending ? _formatIndianAmount(pendingInvoice['amount']) : '0';
    final String monthStr =
        (pendingInvoice['month'] ?? 'November 2026').toString();
    final String dateStr = (pendingInvoice['date'] ?? '-').toString();

    final Gradient topBannerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [Color(0xFF1E4441), Color(0xFF252F37)]
          : const [Color(0xFFEFF7F6), Color(0xFFFFFFFF)],
    );

    final Color iconBoxBorder =
        isDark ? const Color(0xFF476261) : const Color(0xFFD5E7E4);
    final Color iconBoxBg = isDark ? const Color(0xFF252F37) : Colors.white;

    final popAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.08, 0.72, curve: Curves.easeOutBack),
    );

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? borderCol : const Color(0xFFE6ECEA),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.12)
                : const Color(0x070E1A1F),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(gradient: topBannerGradient),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'CURRENT CYCLE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeThemeTokens.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.85,
                            color: tealCol,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: iconBoxBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: iconBoxBorder, width: 1),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: tealCol,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedBuilder(
                        animation: popAnimation,
                        builder: (context, child) {
                          final double s = disableAnim
                              ? 1.0
                              : (0.90 + 0.10 * popAnimation.value);
                          return Transform.scale(
                            scale: s,
                            alignment: Alignment.centerLeft,
                            child: child,
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '₹',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: textPri.withValues(alpha: 0.50),
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              amountText,
                              style: HomeThemeTokens.manrope(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                color: textPri,
                                letterSpacing: -1.4,
                                height: 1.0,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        isPending
                            ? Icons.calendar_today_outlined
                            : Icons.check_circle_outline_rounded,
                        size: 14.5,
                        color: isPending
                            ? HomeThemeTokens.warning(context)
                            : HomeThemeTokens.success(context),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          isPending
                              ? 'Due on $dateStr · $monthStr'
                              : 'All dues cleared for this month',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: HomeThemeTokens.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textSec,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                child: _ScaleTap(
                  onTap: () => _openRentPayment(context, pendingInvoice),
                  child: Semantics(
                    button: true,
                    label: 'Pay rent now',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          Container(
                            constraints: const BoxConstraints(minHeight: 46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? const [
                                        Color(0xFF3FCDB8),
                                        Color(0xFF2AAE9B),
                                      ]
                                    : const [
                                        Color(0xFF0E7A71),
                                        Color(0xFF0B5F59),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.credit_card_outlined,
                                        size: 18,
                                        color: isDark
                                            ? const Color(0xFF04201C)
                                            : Colors.white,
                                      ),
                                      const SizedBox(width: 9),
                                      Flexible(
                                        child: Text(
                                          'Pay rent now',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: HomeThemeTokens.manrope(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? const Color(0xFF04201C)
                                                : Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.14)
                                        : Colors.white.withValues(alpha: 0.18),
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: isDark
                                        ? const Color(0xFF04201C)
                                        : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!disableAnim)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedBuilder(
                                  animation: _sheenController,
                                  builder: (context, _) {
                                    final v = _sheenController.value;
                                    if (v <= 0.0 || v >= 1.0) {
                                      return const SizedBox.shrink();
                                    }
                                    return FractionalTranslation(
                                      translation: Offset(-1.2 + v * 2.6, 0),
                                      child: Container(
                                        width: 84,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Colors.transparent,
                                              Colors.white
                                                  .withValues(alpha: 0.16),
                                              Colors.transparent,
                                            ],
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
                    ),
                  ),
                ),
              )
            else if (_invoices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                child: _ScaleTap(
                  onTap: () => _openReceipt(context, pendingInvoice),
                  child: Semantics(
                    button: true,
                    label: 'View latest receipt',
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: softTealCol,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 16,
                            color: tealCol,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'View latest receipt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HomeThemeTokens.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: tealCol,
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
    );
  }

  Widget _buildInvoiceCard({
    required BuildContext context,
    required Map<String, dynamic> invoice,
    required bool isDark,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required Color tealCol,
  }) {
    final statusStr = (invoice['status'] ?? 'Pending').toString();
    final isPaid = statusStr == 'Paid';
    final isFailed = statusStr == 'Failed';
    final isPendingOrPartial = !isPaid && !isFailed;
    final isTest =
        (invoice['invoice_type'] ?? '').toString().toUpperCase().startsWith('TEST');

    final Color activeBorderCol = isPendingOrPartial
        ? (isDark ? const Color(0xFF2F6F68) : const Color(0xFF9CCBC4))
        : (isFailed
            ? (isDark ? const Color(0xFF6B3A37) : const Color(0xFFF8C9C4))
            : (isDark ? borderCol : const Color(0xFFE8EDEC)));

    final badge = _parseDateBadge(
      invoice['date']?.toString(),
      invoice['month']?.toString(),
    );

    final Color tileBg = isPaid
        ? HomeThemeTokens.successBg(context)
        : (isFailed
            ? HomeThemeTokens.errorBg(context)
            : HomeThemeTokens.warningBg(context));
    final Color tileFg = isPaid
        ? HomeThemeTokens.success(context)
        : (isFailed
            ? HomeThemeTokens.error(context)
            : HomeThemeTokens.warning(context));
    final Color tileBorder = tileFg.withValues(alpha: isDark ? 0.22 : 0.14);

    final String invNumber = (invoice['invoice_number'] ?? '').toString();
    final String invDate = (invoice['date'] ?? '').toString();
    final String subtitleText = invNumber.isNotEmpty
        ? '$invNumber · Due: $invDate'
        : 'Invoice date: $invDate';
    final String notes = (invoice['notes'] ?? '').toString();

    final String displayCardAmount = _formatIndianAmount(invoice['amount']);

    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: activeBorderCol,
          width: isPendingOrPartial ? 1.15 : 1.0,
        ),
        boxShadow: [
          if (isPendingOrPartial)
            BoxShadow(
              color: const Color(0xFF0B6B63)
                  .withValues(alpha: isDark ? 0.12 : 0.055),
              blurRadius: 10,
              spreadRadius: -3,
              offset: const Offset(0, 3),
            )
          else
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.09)
                  : const Color(0x050E1A1F),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Metadata Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Date Pill Box (.mt)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tileBorder, width: 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      badge.monthAbbr,
                      style: HomeThemeTokens.manrope(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.85,
                        color: tileFg,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      badge.day,
                      style: HomeThemeTokens.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: tileFg,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Month Title & Invoice Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            (invoice['month'] ?? 'Current Month').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HomeThemeTokens.manrope(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: textPri,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (isTest) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: HomeThemeTokens.foodBg(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: HomeThemeTokens.foodIcon(context),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              'TEST',
                              style: HomeThemeTokens.manrope(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: HomeThemeTokens.foodIcon(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomeThemeTokens.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                        height: 1.35,
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeThemeTokens.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: tealCol,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Right Amount
              Text(
                '₹$displayCardAmount',
                style: HomeThemeTokens.manrope(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: textPri,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: borderCol),
          const SizedBox(height: 12),
          // Footer Row: Status Chip + Action CTA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPaid)
                        Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: tileFg,
                        )
                      else if (isFailed)
                        Icon(
                          Icons.error_outline_rounded,
                          size: 13,
                          color: tileFg,
                        )
                      else
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (!disableAnim)
                                AnimatedBuilder(
                                  animation: _dotPulseController,
                                  builder: (context, _) {
                                    final t = _dotPulseController.value;
                                    final double ringScale = 1.0 + t * 1.4;
                                    final double ringOpacity = (1.0 - t) * 0.45;
                                    return Transform.scale(
                                      scale: ringScale,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: tileFg.withValues(
                                            alpha: ringOpacity.clamp(0.0, 1.0),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tileFg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          statusStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeThemeTokens.manrope(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: tileFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (isPaid)
                _ScaleTap(
                  onTap: () => _openReceipt(context, invoice),
                  child: Semantics(
                    button: true,
                    label: 'Receipt',
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.transparent : Colors.white,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF476261)
                              : const Color(0xFFCFE3DF),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 15,
                            color: tealCol,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Receipt',
                            style: HomeThemeTokens.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tealCol,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                _ScaleTap(
                  onTap: () => _openRentPayment(context, invoice),
                  child: Semantics(
                    button: true,
                    label: 'Pay now',
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: tealCol,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'Pay now',
                          style: HomeThemeTokens.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF04201C)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required BuildContext context,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required Color tealCol,
    required Color softTealCol,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderCol, width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: softTealCol,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.receipt_long_outlined, color: tealCol, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            'No invoices found',
            style: HomeThemeTokens.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: textPri,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your monthly rent invoices and receipts will show here.',
            textAlign: TextAlign.center,
            style: HomeThemeTokens.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textSec,
            ),
          ),
          const SizedBox(height: 14),
          _ScaleTap(
            onTap: () => _loadInvoicesFromApi(userInitiated: true),
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: softTealCol,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Refresh invoices',
                style: HomeThemeTokens.manrope(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tealCol,
                ),
              ),
            ),
          ),
        ],
      ),
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
        duration:
            disableAnim ? Duration.zero : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
