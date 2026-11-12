import 'package:flutter/material.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion_wrappers.dart';

class RentDepositScreen extends StatefulWidget {
  const RentDepositScreen({super.key});

  @override
  State<RentDepositScreen> createState() => _RentDepositScreenState();
}

class _RentDepositScreenState extends State<RentDepositScreen> {
  late int _rent;
  late int _deposit;
  String _datePaid = '01 Oct 2026 (At Check-in)';

  @override
  void initState() {
    super.initState();
    final resident = AppData.currentResident;
    _rent = (resident['rent'] != null && (int.tryParse(resident['rent'].toString()) ?? 0) > 0)
        ? int.parse(resident['rent'].toString())
        : 8000;
    _deposit = (resident['deposit'] != null && (int.tryParse(resident['deposit'].toString()) ?? 0) > 0)
        ? int.parse(resident['deposit'].toString())
        : 16000;
    _loadRentDepositDetails();
  }

  Future<void> _loadRentDepositDetails() async {
    try {
      final profile = await ResidentApiService.getProfile();
      final stay = profile['stay_details'] as Map<String, dynamic>?;
      if (stay != null && mounted) {
        final r = stay['monthly_rent'];
        final d = stay['security_deposit'];
        final checkIn = stay['check_in_date']?.toString();

        setState(() {
          if (r != null) {
            _rent = (r is num) ? r.toInt() : (int.tryParse(r.toString()) ?? _rent);
          }
          if (d != null) {
            _deposit = (d is num) ? d.toInt() : (int.tryParse(d.toString()) ?? _deposit);
          }
          if (checkIn != null && checkIn.isNotEmpty) {
            final dt = DateTime.tryParse(checkIn);
            if (dt != null) {
              _datePaid = '${dt.day.toString().padLeft(2, '0')} ${_monthName(dt.month)} ${dt.year} (At Check-in)';
            } else {
              _datePaid = '$checkIn (At Check-in)';
            }
          }
        });
      }
    } catch (_) {
      // Graceful fallback to cached values
    }
  }

  static String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final textPri = isDark ? Colors.white : AppTheme.textDark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      appBar: AppBar(
        title: Text(
          'Rent & Deposit Details',
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
            onPressed: _loadRentDepositDetails,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MotionEntrance(
                          child: Text(
                            'Security Deposit',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textPri,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        MotionEntrance(
                          delay: const Duration(milliseconds: 75),
                          child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? const LinearGradient(
                                    colors: [Color(0xFF0F2B26), Color(0xFF134E4A)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark ? const Color(0xFF115E59) : const Color(0xFFBBF7D0),
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0F059669),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'TOTAL DEPOSIT',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF047857),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF064E3B) : const Color(0xFF16A34A),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.shield_rounded, size: 14, color: Colors.white),
                                        SizedBox(width: 5),
                                        Text(
                                          'Active & Secure',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11.5,
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
                                '₹ $_deposit',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: isDark ? Colors.white : const Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Divider(
                                height: 1,
                                color: isDark ? const Color(0xFF115E59) : const Color(0xFF86EFAC),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Fixed Rent',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? const Color(0xFF99F6E4) : const Color(0xFF047857),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹ $_rent / month',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF065F46),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Refund Status',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? const Color(0xFF99F6E4) : const Color(0xFF047857),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '50% Refundable',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF065F46),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date Paid',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFF99F6E4) : const Color(0xFF047857),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _datePaid,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF065F46),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
