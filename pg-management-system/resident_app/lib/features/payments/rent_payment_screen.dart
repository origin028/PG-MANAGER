import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_upi_india/flutter_upi_india.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/data/app_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/payment_verification_service.dart';
import '../../core/services/resident_api_service.dart';

class RentPaymentScreen extends StatefulWidget {
  final Map<String, dynamic>? invoiceData;

  const RentPaymentScreen({super.key, this.invoiceData});

  /// Calculates the exact remaining payable amount from an invoice map.
  /// Checks balance_amount, remaining_amount, amount, and total_amount.
  /// Handles both num and String safely and defaults to 8000.0 only if unparseable.
  static double calculatePayableAmount(Map<String, dynamic>? invoice) {
    if (invoice == null) return 8000.0;
    final candidates = [
      invoice['balance_amount'],
      invoice['remaining_amount'],
      invoice['amount'],
      invoice['total_amount'],
    ];
    for (final val in candidates) {
      if (val != null) {
        if (val is num) {
          final d = val.toDouble();
          if (d > 0) return d;
        } else if (val is String) {
          final d = double.tryParse(val.trim());
          if (d != null && d > 0) return d;
        }
      }
    }
    return 8000.0;
  }

  /// Formats a clean, readable transaction note adhering to NPCI standards.
  /// If [invoiceId] is a full UUID, uses the first 8 characters to stay well within
  /// NPCI length limits while uniquely identifying the invoice.
  static String formatTransactionNote({
    required String invoiceId,
    required String payeeName,
  }) {
    final cleanId = invoiceId.trim();
    final displayId = cleanId.length > 8 && !cleanId.toUpperCase().startsWith('INV-')
        ? cleanId.substring(0, 8)
        : cleanId;
    return 'Rent Payment - $displayId - ${payeeName.trim()}';
  }

  /// Builds a standard NPCI-compliant UPI URI using UTF-8 URL percent-encoding.
  /// Follows the official NPCI UPI Linking Specification.
  ///
  /// Query parameters are properly URL-encoded (RFC 3986 percent-encoded UTF-8)
  /// ensuring spaces are encoded as '%20' rather than '+', so receiving UPI apps
  /// (Google Pay, PhonePe, Navi, Paytm, etc.) decode the transaction note
  /// into human-readable text instead of displaying literal '+' characters.
  ///
  /// Standard parameters:
  ///   - pa: Payee VPA / UPI ID (e.g. masisokatali90900@okaxis) [Mandatory]
  ///   - pn: Payee Name (e.g. Saukatali Masi) [Mandatory]
  ///   - am: Exact amount formatted to 2 decimal places (e.g. 1.00 or 8000.00) [Mandatory]
  ///   - cu: Currency code (strictly 'INR') [Mandatory]
  ///   - tn: Meaningful transaction note / description [Recommended]
  ///   - tr: Unique Transaction Reference / Order Reference [NPCI Intent Specification]
  ///   - mc: Merchant Category Code (4-digit MCC, if registered merchant) [Optional]
  static Uri buildUpiUri({
    required String payeeVpa,
    required String payeeName,
    required double amount,
    String currency = 'INR',
    String? transactionNote,
    String? transactionRef,
    String? merchantCode,
  }) {
    final queryParams = <String, String>{
      'pa': payeeVpa.trim(),
      'pn': payeeName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': currency.trim(),
    };

    if (transactionNote != null && transactionNote.trim().isNotEmpty) {
      queryParams['tn'] = transactionNote.trim();
    }

    if (transactionRef != null && transactionRef.trim().isNotEmpty) {
      queryParams['tr'] = transactionRef.trim();
    }

    if (merchantCode != null && merchantCode.trim().isNotEmpty) {
      queryParams['mc'] = merchantCode.trim();
    }

    // Use RFC 3986 UTF-8 percent-encoding for query components.
    // Spaces become '%20', NOT '+' (application/x-www-form-urlencoded).
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return Uri(
      scheme: 'upi',
      host: 'pay',
      query: queryString,
    );
  }

  /// Official Android package name for PhonePe.
  static const String phonePePackage = 'com.phonepe.app';

  /// Constructs an Android Intent URI explicitly targeting PhonePe (com.phonepe.app).
  /// Ensures the Android OS launches PhonePe directly instead of an ambiguous chooser.
  static Uri buildPhonePeIntentUri({
    required String payeeVpa,
    required String payeeName,
    required double amount,
    String currency = 'INR',
    String? transactionNote,
    String? transactionRef,
    String? merchantCode,
  }) {
    final note = transactionNote?.trim();
    final ref = transactionRef?.trim();
    final mc = merchantCode?.trim();
    final query = <String, String>{
      'pa': payeeVpa.trim(),
      'pn': payeeName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': currency.trim(),
      if (note != null && note.isNotEmpty) 'tn': note,
      if (ref != null && ref.isNotEmpty) 'tr': ref,
      if (mc != null && mc.isNotEmpty) 'mc': mc,
    };
    final queryString = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return Uri.parse('intent://pay?$queryString#Intent;scheme=upi;package=$phonePePackage;end');
  }

  @override
  State<RentPaymentScreen> createState() => _RentPaymentScreenState();
}

class _RentPaymentScreenState extends State<RentPaymentScreen> {
  // Verified payee details
  static const String defaultPayeeUpiId = 'masisokatali90900@okaxis';
  static const String defaultPayeeName = "Saukatali Masi";
  static const String defaultCurrency = 'INR';

  late final Map<String, dynamic> _invoice;
  String _ownerUpiId = defaultPayeeUpiId;
  String _payeeName = defaultPayeeName;
  String? _merchantCode;
  bool _isMerchantConfigured = false;
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    final rent = AppData.currentResident['rent'] != null && AppData.currentResident['rent'] != 0
        ? AppData.currentResident['rent']
        : 8000;

    _invoice = widget.invoiceData ?? {
      'id': 'INV-2026-010',
      'month': 'November 2026',
      'amount': rent,
      'date': '05 Nov 2026',
      'status': 'Pending',
    };

    _loadOwnerUpi();

    // Automatically open the payment options modal when navigating from Pay Now
    if (widget.invoiceData?['autoOpen'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPaymentInterfaceModal();
        }
      });
    }
  }

  Future<void> _loadOwnerUpi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final upi = prefs.getString('admin_upi_id');
      if (upi != null && upi.trim().isNotEmpty) {
        setState(() => _ownerUpiId = upi.trim());
      }
      final name = prefs.getString('admin_payee_name');
      if (name != null && name.trim().isNotEmpty) {
        setState(() => _payeeName = name.trim());
      }
      final mc = prefs.getString('admin_merchant_code');
      if (mc != null && mc.trim().isNotEmpty) {
        setState(() {
          _merchantCode = mc.trim();
          _isMerchantConfigured = true;
        });
      }
    } catch (_) {}
  }

  String _formatAmount(dynamic amt) {
    if (amt == null) return '0.00';
    final num val = amt is num ? amt : (num.tryParse(amt.toString()) ?? 0);
    if (val % 1 == 0 && val >= 100) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(2);
  }

  Future<void> _handlePaymentMethodSelection(String paymentApp, String appScheme) async {
    if (_isLaunching) return; // Prevent duplicate taps

    setState(() => _isLaunching = true);

    try {
      final invoiceId = _invoice['id']?.toString() ?? 'INV-2026-010';
      final double amount = RentPaymentScreen.calculatePayableAmount(_invoice);
      final txnRef = PaymentVerificationService.generateTxnReference(invoiceId);

      // =========================================================================
      // SEPARATE FLOW 1: DEMO ONLINE PAYMENT (Instant local / test settlement)
      // =========================================================================
      if (paymentApp == 'Demo Pay') {
        if (!invoiceId.startsWith('INV-')) {
          try {
            await ResidentApiService.payDemo(
              invoiceId: invoiceId,
              amount: amount,
              idempotencyKey: 'DEMO-$txnRef',
            );
          } catch (e) {
            debugPrint('API payDemo error: $e');
          }
        }

        await PaymentVerificationService.initiatePayment(
          invoiceId: invoiceId,
          amount: amount,
          paymentApp: paymentApp,
          txnRef: txnRef,
        );

        if (!mounted) return;
        setState(() => _isLaunching = false);
        _navigateToStatusScreen(
          paymentApp: paymentApp,
          txnRef: txnRef,
          isDemo: true,
        );
        return;
      }

      // =========================================================================
      // SEPARATE FLOW 2: DEDICATED PHONEPE PACKAGE FLOW (com.phonepe.app)
      // =========================================================================
      if (paymentApp == 'PhonePe' || paymentApp == 'Pay using PhonePe') {
        setState(() => _isLaunching = false);
        await _handlePhonePePayment();
        return;
      }

      // =========================================================================
      // SEPARATE FLOW 3: REAL UPI INTENT FLOW (Google Pay, System UPI / Navi)
      // =========================================================================
      final init = await _initiateAuthoritativePayment(paymentApp);
      final backendPaymentId = init.backendPaymentId;

      // 3. Construct clean, NPCI-standard UPI deep link URI
      final note = RentPaymentScreen.formatTransactionNote(
        invoiceId: invoiceId,
        payeeName: _payeeName,
      );
      final upiUri = RentPaymentScreen.buildUpiUri(
        payeeVpa: _ownerUpiId,
        payeeName: _payeeName,
        amount: amount,
        currency: defaultCurrency,
        transactionNote: note,
        transactionRef: txnRef,
        merchantCode: _merchantCode,
      );

      // Diagnostic logging of all required attributes immediately before launch
      final rawAmount = _invoice['amount'];
      final rawBalance = _invoice['balance_amount'];
      final rawAmountType = rawAmount?.runtimeType.toString() ?? 'null';
      final rawBalanceType = rawBalance?.runtimeType.toString() ?? 'null';

      debugPrint('==================== [UPI INTENT DIAGNOSTICS] ====================');
      debugPrint('[UPI Diagnostics] Actual Invoice ID: $invoiceId');
      debugPrint('[UPI Diagnostics] Raw Invoice Amount: $rawAmount (runtime type: $rawAmountType)');
      debugPrint('[UPI Diagnostics] Raw Balance Amount: $rawBalance (runtime type: $rawBalanceType)');
      debugPrint('[UPI Diagnostics] Remaining Amount: ₹${amount.toStringAsFixed(2)}');
      debugPrint('[UPI Diagnostics] Final Payment Amount: ₹${amount.toStringAsFixed(2)}');
      debugPrint('[UPI Diagnostics] Target Payee VPA: $_ownerUpiId');
      debugPrint('[UPI Diagnostics] Target Payee Name: $_payeeName');
      debugPrint('[UPI Diagnostics] Is Merchant Configured: $_isMerchantConfigured');
      debugPrint('[UPI Diagnostics] Merchant Category Code (mc): ${_merchantCode ?? "None (Personal VPA - Bank limits apply for Mode 04)"}');
      debugPrint('[UPI Diagnostics] Selected UPI App: $paymentApp (scheme: $appScheme)');
      debugPrint('[UPI Diagnostics] Transaction Ref (tr): $txnRef');
      debugPrint('[UPI Diagnostics] Final Encoded UPI URI: $upiUri');
      debugPrint('==================================================================');

      bool launched = false;

      // 4. Launch Android UPI Intent
      try {
        if (await canLaunchUrl(upiUri)) {
          launched = await launchUrl(upiUri, mode: LaunchMode.externalNonBrowserApplication);
        } else {
          try {
            launched = await launchUrl(upiUri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[UPI Intent] Error launching UPI application: $e');
      }

      debugPrint('[UPI Diagnostics] Launch Method: url_launcher.launchUrl(mode: LaunchMode.externalNonBrowserApplication)');
      debugPrint('[UPI Diagnostics] Launch Result: ${launched ? 'SUCCESS (intent dispatched to Android OS)' : 'FAILED (app not found / rejected)'}');

      if (!mounted) return;
      setState(() => _isLaunching = false);

      // 5. If app is unavailable, present helpful fallback message & copy UPI ID
      if (!launched) {
        _showUpiAppUnavailableDialog(
          paymentApp: paymentApp,
          amount: amount,
          invoiceId: invoiceId,
        );
        return;
      }

      // 6. Record app return on backend: strict rule -> sets state to PENDING_VERIFICATION (NOT paid)
      if (backendPaymentId != null) {
        ResidentApiService.recordUpiReturn(backendPaymentId).catchError((_) => <String, dynamic>{});
      }

      // 7. Directly display Payment Status screen (strictly Pending Bank Verification)
      _navigateToStatusScreen(
        paymentApp: paymentApp,
        txnRef: txnRef,
        paymentId: backendPaymentId,
        isDemo: false,
      );
    } catch (e) {
      debugPrint('[UPI Intent] Error in payment selection: $e');
      if (!mounted) return;
      setState(() => _isLaunching = false);
    }
  }

  // ===========================================================================
  // AUTHORITATIVE BACKEND INITIATION HELPER
  // ===========================================================================
  Future<({String? backendPaymentId, String txnRef, double amount, String invoiceId})>
      _initiateAuthoritativePayment(String paymentApp) async {
    final invoiceId = _invoice['id']?.toString() ?? 'INV-2026-010';
    final double amount = RentPaymentScreen.calculatePayableAmount(_invoice);
    final txnRef = PaymentVerificationService.generateTxnReference(invoiceId);
    String? backendPaymentId;

    if (!invoiceId.startsWith('INV-')) {
      try {
        final initiateRes = await ResidentApiService.initiateDirectUpiPayment(
          invoiceId: invoiceId,
          idempotencyKey: 'UPI-$txnRef',
        );
        if (initiateRes.isNotEmpty) {
          backendPaymentId = initiateRes['payment_id']?.toString();
          if (initiateRes['payee_vpa'] != null && initiateRes['payee_vpa'].toString().trim().isNotEmpty) {
            _ownerUpiId = initiateRes['payee_vpa'].toString().trim();
          }
          if (initiateRes['payee_name'] != null && initiateRes['payee_name'].toString().trim().isNotEmpty) {
            _payeeName = initiateRes['payee_name'].toString().trim();
          }
          if (initiateRes['merchant_code'] != null && initiateRes['merchant_code'].toString().trim().isNotEmpty) {
            _merchantCode = initiateRes['merchant_code'].toString().trim();
          }
          if (initiateRes['is_merchant_configured'] != null) {
            _isMerchantConfigured = initiateRes['is_merchant_configured'] == true;
          }
        }
      } catch (e) {
        debugPrint('API initiateDirectUpiPayment error: $e');
      }
    }

    await PaymentVerificationService.initiatePayment(
      invoiceId: invoiceId,
      amount: amount,
      paymentApp: paymentApp,
      txnRef: txnRef,
      paymentId: backendPaymentId,
    );

    return (
      backendPaymentId: backendPaymentId,
      txnRef: txnRef,
      amount: amount,
      invoiceId: invoiceId,
    );
  }

  // ===========================================================================
  // METHOD 1: COPY UPI ID + OPEN GOOGLE PAY (Mode 00 Enabler)
  // ===========================================================================
  Future<void> _handleCopyAndOpenGooglePay() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    try {
      final init = await _initiateAuthoritativePayment('Google Pay (Copy & Open)');

      // Auto-copy verified payee UPI ID to clipboard
      try {
        await Clipboard.setData(ClipboardData(text: _ownerUpiId));
      } catch (e) {
        debugPrint('[Copy & Open GPay] Clipboard error: $e');
      }

      if (!mounted) return;
      setState(() => _isLaunching = false);

      _showCopyAndOpenGPayDialog(
        invoiceId: init.invoiceId,
        amount: init.amount,
        txnRef: init.txnRef,
        backendPaymentId: init.backendPaymentId,
      );
    } catch (e) {
      debugPrint('[Copy & Open GPay] Error: $e');
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  void _showCopyAndOpenGPayDialog({
    required String invoiceId,
    required double amount,
    required String txnRef,
    String? backendPaymentId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = AppTheme.isDark(sheetCtx);
        final cardBg = AppTheme.cardBg(sheetCtx);
        final textPri = AppTheme.textPrimary(sheetCtx);
        final textSec = AppTheme.textSecondary(sheetCtx);
        final formattedAmt = _formatAmount(amount);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x33000000) : Colors.black12,
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.g_mobiledata_rounded, color: Color(0xFF4285F4), size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pay using Google Pay',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: textPri,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'UPI ID auto-copied to clipboard',
                              style: TextStyle(fontSize: 12, color: AppTheme.successGreen, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '₹ $formattedAmt',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF93C5FD) : AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Payee Details Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Recipient Name', style: TextStyle(fontSize: 12, color: textSec)),
                            Text(_payeeName, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textPri)),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Payee UPI ID (VPA)', style: TextStyle(fontSize: 11, color: textSec)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _ownerUpiId,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPri),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _ownerUpiId));
                                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  const SnackBar(content: Text('UPI ID copied to clipboard!'), duration: Duration(seconds: 2)),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: const Text('Copy'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Payable Amount', style: TextStyle(fontSize: 12, color: textSec)),
                            Row(
                              children: [
                                Text(
                                  '₹ $formattedAmt',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.primaryBlue),
                                  tooltip: 'Copy Amount',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: formattedAmt));
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(content: Text('Amount ₹$formattedAmt copied to clipboard!'), duration: const Duration(seconds: 2)),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Numbered Instructions
                  Text('How to complete your payment:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPri)),
                  const SizedBox(height: 8),
                  _buildStepItem(1, 'Tap "Open Google Pay App" below.', textPri, textSec),
                  _buildStepItem(2, 'In Google Pay, tap "Pay UPI ID or number".', textPri, textSec),
                  _buildStepItem(3, 'Paste the copied UPI ID: $_ownerUpiId.', textPri, textSec),
                  _buildStepItem(4, 'Verify recipient name is "$_payeeName".', textPri, textSec),
                  _buildStepItem(5, 'Enter the exact amount ₹$formattedAmt and complete with UPI PIN.', textPri, textSec),
                  const SizedBox(height: 14),

                  // Important Notice: Never claim prefilled or completed
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notice: Payment details are not automatically prefilled in Google Pay in manual mode. Please enter the exact amount manually. Returning here does not mark the invoice as paid.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Primary Button: Open Google Pay App
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final gpayUri = Uri.parse('android-app://com.google.android.apps.nbu.paisa.user');
                        final fallbackUri = Uri.parse('upi://pay');
                        bool launched = false;
                        try {
                          if (await canLaunchUrl(gpayUri)) {
                            launched = await launchUrl(gpayUri, mode: LaunchMode.externalNonBrowserApplication);
                          }
                        } catch (_) {}
                        if (!launched) {
                          try {
                            if (await canLaunchUrl(fallbackUri)) {
                              launched = await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                            }
                          } catch (_) {}
                        }
                        if (!launched) {
                          if (sheetCtx.mounted) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(content: Text('Could not open Google Pay directly. Please open Google Pay manually.')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.launch_rounded, size: 18),
                      label: const Text('Open Google Pay App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Secondary Button: I Have Paid / Check Status
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        if (backendPaymentId != null) {
                          ResidentApiService.recordUpiReturn(backendPaymentId).catchError((_) => <String, dynamic>{});
                        }
                        _navigateToStatusScreen(
                          paymentApp: 'Google Pay (Copy & Open)',
                          txnRef: txnRef,
                          paymentId: backendPaymentId,
                          isDemo: false,
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: const Text('I Have Paid / Check Status', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Close Button
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text('Close', style: TextStyle(color: textSec, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // DEDICATED PHONEPE PAYMENT ACTION (Targeted com.phonepe.app)
  // ===========================================================================
  Future<void> _handlePhonePePayment() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    try {
      final init = await _initiateAuthoritativePayment('PhonePe');
      final invoiceId = init.invoiceId;
      final amount = init.amount;
      final txnRef = init.txnRef;
      final backendPaymentId = init.backendPaymentId;
      final note = RentPaymentScreen.formatTransactionNote(
        invoiceId: invoiceId,
        payeeName: _payeeName,
      );

      final upiUri = RentPaymentScreen.buildUpiUri(
        payeeVpa: _ownerUpiId,
        payeeName: _payeeName,
        amount: amount,
        currency: defaultCurrency,
        transactionNote: note,
        transactionRef: txnRef,
        merchantCode: _merchantCode,
      );

      debugPrint('==================== [PHONEPE INTENT DIAGNOSTICS] ====================');
      debugPrint('[PhonePe Diagnostics] Invoice ID: $invoiceId');
      debugPrint('[PhonePe Diagnostics] Payable Amount: ₹${amount.toStringAsFixed(2)}');
      debugPrint('[PhonePe Diagnostics] Target Package: ${RentPaymentScreen.phonePePackage}');
      debugPrint('[PhonePe Diagnostics] Payee VPA: $_ownerUpiId');
      debugPrint('[PhonePe Diagnostics] Payee Name: $_payeeName');
      debugPrint('[PhonePe Diagnostics] Transaction Ref: $txnRef');
      debugPrint('[PhonePe Diagnostics] Standard UPI URI: $upiUri');
      debugPrint('======================================================================');

      bool launched = false;
      bool channelExecuted = false;

      // Stage 1: Explicit Android Native Platform Channel targeting com.phonepe.app
      try {
        const nativeUpiChannel = MethodChannel('com.originpg.resident/native_upi');
        final nativeRes = await nativeUpiChannel.invokeMapMethod<String, dynamic>(
          'launchPhonePeDirect',
          {
            'uri': upiUri.toString(),
            'package': RentPaymentScreen.phonePePackage,
            'payeeVpa': _ownerUpiId,
            'payeeName': _payeeName,
            'amount': amount.toStringAsFixed(2),
            'txnRef': txnRef,
            'note': note,
          },
        );
        if (nativeRes != null) {
          channelExecuted = true;
          if (nativeRes['status'] == 'SUCCESS') {
            launched = true;
            debugPrint('[PhonePe Direct] Native channel launched successfully via ${nativeRes['method']}');
          } else {
            debugPrint('[PhonePe Direct] Native channel result: $nativeRes');
          }
        }
      } catch (e) {
        debugPrint('[PhonePe Direct] Native channel unavailable or error: $e');
      }

      // If Android native channel was not available, try URL fallbacks strictly for PhonePe
      if (!channelExecuted) {
        // Stage 2: PhonePe custom scheme URI (phonepe://pay?...) with url_launcher (preserves %20 encoding)
        final phonePeSchemeUri = upiUri.replace(scheme: 'phonepe');
        try {
          if (await canLaunchUrl(phonePeSchemeUri)) {
            launched = await launchUrl(phonePeSchemeUri, mode: LaunchMode.externalNonBrowserApplication);
            debugPrint('[PhonePe Direct] Launched via phonepe:// scheme URI: $launched');
          }
        } catch (e) {
          debugPrint('[PhonePe Direct] phonepe:// scheme launch error: $e');
        }

        // Stage 3: PhonePe custom scheme URI (ppe://pay?...) with url_launcher (preserves %20 encoding)
        if (!launched) {
          final ppeSchemeUri = upiUri.replace(scheme: 'ppe');
          try {
            if (await canLaunchUrl(ppeSchemeUri)) {
              launched = await launchUrl(ppeSchemeUri, mode: LaunchMode.externalNonBrowserApplication);
              debugPrint('[PhonePe Direct] Launched via ppe:// scheme URI: $launched');
            }
          } catch (e) {
            debugPrint('[PhonePe Direct] ppe:// scheme launch error: $e');
          }
        }

        // Stage 4: Native startActivityForResult via flutter_upi_india with explicit package
        if (!launched) {
          try {
            final res = await UpiPay.initiateTransaction(
              app: UpiApplication.phonePe,
              receiverUpiAddress: _ownerUpiId,
              receiverName: _payeeName,
              transactionRef: txnRef,
              amount: amount.toStringAsFixed(2),
              transactionNote: note,
              merchantCode: _merchantCode,
            );
            final raw = res.rawResponse ?? '';
            if (raw.isNotEmpty && raw != 'activity_unavailable' && raw != 'failed_to_open_app') {
              launched = true;
              debugPrint('[PhonePe Direct] UpiPay.initiateTransaction launched successfully: $raw');
            } else {
              debugPrint('[PhonePe Direct] UpiPay returned: $raw');
            }
          } catch (e) {
            debugPrint('[PhonePe Direct] flutter_upi_india launch error: $e');
          }
        }
      }

      // STRICT RULE: NEVER fall back to generic upi:// chooser or &package= query param!
      // If PhonePe cannot be opened directly, show clear error dialog with option to use other apps.

      if (!mounted) return;
      setState(() => _isLaunching = false);

      // Safe fallback if PhonePe is not available on device
      if (!launched) {
        _showPhonePeUnavailableDialog(
          amount: amount,
          invoiceId: invoiceId,
        );
        return;
      }

      // Strictly set state to PENDING_VERIFICATION on backend (never automatically marked PAID)
      if (backendPaymentId != null) {
        ResidentApiService.recordUpiReturn(backendPaymentId).catchError((_) => <String, dynamic>{});
      }

      // Navigate to Payment Status screen strictly in PENDING_VERIFICATION
      _navigateToStatusScreen(
        paymentApp: 'PhonePe',
        txnRef: txnRef,
        paymentId: backendPaymentId,
        isDemo: false,
      );
    } catch (e) {
      debugPrint('[PhonePe Action] Unexpected error: $e');
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  void _showPhonePeUnavailableDialog({
    required double amount,
    required String invoiceId,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.payments_rounded, color: Color(0xFF5F259F), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'PhonePe Not Available',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The PhonePe application (com.phonepe.app) could not be opened directly on your device.\n\n'
              'You can copy the PG Owner UPI ID below to pay, or select another UPI application (like Navi or Paytm).',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textGrey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payee UPI ID', style: TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                        const SizedBox(height: 2),
                        Text(
                          _ownerUpiId,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryBlue),
                    tooltip: 'Copy UPI ID',
                    onPressed: () {
                      try {
                        Clipboard.setData(ClipboardData(text: _ownerUpiId));
                      } catch (_) {}
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UPI ID copied to clipboard!'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handlePaymentMethodSelection('Other UPI', 'upi');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Use Other UPI App'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // METHOD 2: DYNAMIC UPI QR CODE (Mode 01 Enabler)
  // ===========================================================================
  Future<void> _handleDynamicQrCode() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    try {
      final init = await _initiateAuthoritativePayment('Dynamic UPI QR');

      if (!mounted) return;
      setState(() => _isLaunching = false);

      _showDynamicQrDialog(
        invoiceId: init.invoiceId,
        amount: init.amount,
        txnRef: init.txnRef,
        backendPaymentId: init.backendPaymentId,
      );
    } catch (e) {
      debugPrint('[Dynamic QR] Error: $e');
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  void _showDynamicQrDialog({
    required String invoiceId,
    required double amount,
    required String txnRef,
    String? backendPaymentId,
  }) {
    final note = RentPaymentScreen.formatTransactionNote(
      invoiceId: invoiceId,
      payeeName: _payeeName,
    );
    final upiUri = RentPaymentScreen.buildUpiUri(
      payeeVpa: _ownerUpiId,
      payeeName: _payeeName,
      amount: amount,
      currency: defaultCurrency,
      transactionNote: note,
      transactionRef: txnRef,
      merchantCode: _merchantCode,
    );
    final upiUriString = upiUri.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = AppTheme.isDark(sheetCtx);
        final cardBg = AppTheme.cardBg(sheetCtx);
        final textPri = AppTheme.textPrimary(sheetCtx);
        final textSec = AppTheme.textSecondary(sheetCtx);
        final formattedAmt = _formatAmount(amount);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x33000000) : Colors.black12,
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Drag Handle
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Text(
                    'Dynamic UPI QR Code',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPri),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Scan with any UPI app to pay ₹$formattedAmt',
                    style: TextStyle(fontSize: 12.5, color: textSec),
                  ),
                  const SizedBox(height: 16),

                  // High-Contrast QR Code Display
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: upiUriString,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Payee & Invoice Summary
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Payee', style: TextStyle(fontSize: 12, color: textSec)),
                            Text(_payeeName, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textPri)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('UPI ID', style: TextStyle(fontSize: 12, color: textSec)),
                            Text(_ownerUpiId, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Invoice ID', style: TextStyle(fontSize: 12, color: textSec)),
                            Text(invoiceId, style: TextStyle(fontSize: 12, color: textPri)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Amount', style: TextStyle(fontSize: 12, color: textSec)),
                            Text('₹ $formattedAmt', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Clear Instructions for scanning
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.qr_code_scanner_rounded, size: 16, color: Color(0xFF1D4ED8)),
                            SizedBox(width: 6),
                            Text(
                              'How to scan this QR Code:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '• Scan using Google Pay, PhonePe, Paytm, or BHIM on another phone.\n'
                          '• Or take a screenshot and use "Scan from Gallery / Upload QR" in your UPI app.\n'
                          '• Note: A phone cannot scan a QR code displayed directly on its own screen.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF1E3A8A), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions: Save QR & Share QR
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: upiUriString));
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text('UPI QR Code link saved to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.save_alt_rounded, size: 16),
                          label: const Text('Save QR Link'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final shareText = 'Rent Payment for $invoiceId\n'
                                'Payee: $_payeeName\n'
                                'UPI ID: $_ownerUpiId\n'
                                'Amount: ₹$formattedAmt\n'
                                'UPI URI: $upiUriString';
                            Clipboard.setData(ClipboardData(text: shareText));
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text('Payment details copied to share!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.share_rounded, size: 16),
                          label: const Text('Share Details'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Button: I Have Paid / Check Status
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        if (backendPaymentId != null) {
                          ResidentApiService.recordUpiReturn(backendPaymentId).catchError((_) => <String, dynamic>{});
                        }
                        _navigateToStatusScreen(
                          paymentApp: 'Dynamic UPI QR',
                          txnRef: txnRef,
                          paymentId: backendPaymentId,
                          isDemo: false,
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('I Have Transferred / Confirm Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Close Button
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: Text('Close', style: TextStyle(color: textSec, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepItem(int stepNumber, String text, Color textPri, Color textSec) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$stepNumber',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: textSec, height: 1.3)),
          ),
        ],
      ),
    );
  }

  void _showUpiAppUnavailableDialog({
    required String paymentApp,
    required double amount,
    required String invoiceId,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$paymentApp Not Available',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$paymentApp or a compatible UPI payment application was not found on your device.\n\n'
              'You can copy the PG Owner UPI ID below to pay directly from your mobile banking app, '
              'or test the payment using Demo Online Payment.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textGrey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payee UPI ID', style: TextStyle(fontSize: 10, color: AppTheme.textGrey)),
                        const SizedBox(height: 2),
                        Text(
                          _ownerUpiId,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryBlue),
                    tooltip: 'Copy UPI ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _ownerUpiId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UPI ID copied to clipboard!'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handlePaymentMethodSelection('Demo Pay', 'demo');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Use Demo Pay'),
          ),
        ],
      ),
    );
  }

  void _navigateToStatusScreen({
    required String paymentApp,
    required String txnRef,
    String? paymentId,
    required bool isDemo,
  }) {
    final amount = RentPaymentScreen.calculatePayableAmount(_invoice);
    try {
      context.push(
        '/payment-status',
        extra: {
          'invoiceId': _invoice['id'] ?? 'INV-2026-010',
          'amount': amount,
          'paymentApp': paymentApp,
          'txnRef': txnRef,
          'paymentId': paymentId,
          'isDemo': isDemo,
          'dueDate': _invoice['date'] ?? '05 Nov 2026',
          'month': _invoice['month'] ?? 'November 2026',
          'autoPoll': true,
        },
      );
    } catch (e) {
      debugPrint('[Navigation] Status screen push error: $e');
    }
  }

  void _showPaymentInterfaceModal() {
    final amount = RentPaymentScreen.calculatePayableAmount(_invoice);
    final month = _invoice['month'] ?? 'November 2026';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final isDark = AppTheme.isDark(bottomSheetContext);
        final cardBg = AppTheme.cardBg(bottomSheetContext);
        final textPri = AppTheme.textPrimary(bottomSheetContext);
        final textSec = AppTheme.textSecondary(bottomSheetContext);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x33000000) : Colors.black12,
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Amount & Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payment Options',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textPri,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Rent Due • $month',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: textSec,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? const Color(0xFF3B82F6) : const Color(0xFFDBEAFE)),
                        ),
                        child: Text(
                          '₹ ${_formatAmount(amount)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? const Color(0xFF93C5FD) : AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Select PhonePe or Google Pay, or another UPI application to pay $_payeeName directly.',
                    style: TextStyle(fontSize: 12.5, color: textSec, height: 1.3),
                  ),
                  const SizedBox(height: 18),

                  // Method 1: Google Pay (Copy UPI ID & Open)
                  _buildModalPaymentOption(
                    title: 'Pay using Google Pay',
                    subtitle: 'Auto-copies UPI ID & opens Google Pay for reliable transfer',
                    brandColor: const Color(0xFF4285F4),
                    iconData: Icons.g_mobiledata_rounded,
                    isIconLetter: true,
                    context: bottomSheetContext,
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _handleCopyAndOpenGooglePay();
                    },
                  ),
                  const SizedBox(height: 10),

                  // Method 2: Dynamic UPI QR Code
                  _buildModalPaymentOption(
                    title: 'Dynamic UPI QR Code',
                    subtitle: 'Scan to pay with another phone or from gallery',
                    brandColor: const Color(0xFF0F766E),
                    iconData: Icons.qr_code_2_rounded,
                    isIconLetter: false,
                    context: bottomSheetContext,
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _handleDynamicQrCode();
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Google Pay (Verified Real UPI)
                  _buildModalPaymentOption(
                    title: 'Google Pay',
                    subtitle: 'Opens Google Pay app directly to pay',
                    brandColor: const Color(0xFF4285F4),
                    iconData: Icons.launch_rounded,
                    isIconLetter: false,
                    context: bottomSheetContext,
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _handlePaymentMethodSelection('Google Pay', 'gpay');
                    },
                  ),
                  const SizedBox(height: 10),

                  // Dedicated PhonePe Direct Action (com.phonepe.app)
                  _buildModalPaymentOption(
                    title: 'Pay using PhonePe',
                    subtitle: 'Opens PhonePe app directly to pay',
                    brandColor: const Color(0xFF5F259F),
                    iconData: Icons.payments_rounded,
                    isIconLetter: false,
                    context: bottomSheetContext,
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _handlePaymentMethodSelection('Pay using PhonePe', 'phonepe');
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Other Installed UPI Apps
                  _buildModalPaymentOption(
                    title: 'Any Installed UPI App',
                    subtitle: 'Paytm, BHIM, CRED or any bank UPI application',
                    brandColor: const Color(0xFF0284C7),
                    iconData: Icons.account_balance_rounded,
                    isIconLetter: false,
                    context: bottomSheetContext,
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _handlePaymentMethodSelection('Other UPI', 'upi');
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 4: Demo Online Payment (Separated Test Mode)
                  _buildModalPaymentOption(
                    title: 'Demo Online Payment',
                    subtitle: 'Instant test settlement without opening external UPI apps',
                    brandColor: const Color(0xFF10B981),
                    iconData: Icons.science_rounded,
                    isIconLetter: false,
                    context: bottomSheetContext,
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _handlePaymentMethodSelection('Demo Pay', 'demo');
                    },
                  ),
                  const SizedBox(height: 18),

                  // Security Note
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.shield_rounded, color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF16A34A), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '100% Secure bank-to-bank UPI payment to $_ownerUpiId. No gateway surcharge.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Cancel Button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(bottomSheetContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: textSec,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalPaymentOption({
    required String title,
    required String subtitle,
    required Color brandColor,
    required IconData iconData,
    required bool isIconLetter,
    required VoidCallback onTap,
    BuildContext? context,
  }) {
    final isDark = context != null ? AppTheme.isDark(context) : false;
    final cardBg = context != null ? AppTheme.cardBg(context) : Colors.white;
    final borderCol = context != null ? AppTheme.borderCol(context) : const Color(0xFFE2E8F0);
    final textPri = context != null ? AppTheme.textPrimary(context) : AppTheme.textDark;
    final textSec = context != null ? AppTheme.textSecondary(context) : AppTheme.textGrey;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x1A000000) : const Color(0x05000000),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: brandColor.withValues(alpha: 0.25)),
                  ),
                  child: Center(
                    child: Icon(
                      iconData,
                      size: isIconLetter ? 28 : 20,
                      color: brandColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: textSec,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = RentPaymentScreen.calculatePayableAmount(_invoice);
    final invoiceId = _invoice['id'] ?? 'INV-2026-010';
    final dueDate = _invoice['date'] ?? '05 Nov 2026';
    final month = _invoice['month'] ?? 'November 2026';

    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final borderCol = AppTheme.borderCol(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final pageBg = AppTheme.pageBg(context);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text('Rent Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPri)),
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
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rent Amount Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x403F51B5),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL RENT DUE',
                              style: TextStyle(
                                color: Color(0xFFA5B4FC),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x26FFFFFF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(
                                month,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '₹ ${_formatAmount(amount)}',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, thickness: 1, color: Colors.white24),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Invoice ID', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(invoiceId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Due Date', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(dueDate, style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // PG / Verified Owner Payee Details Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x1A000000) : const Color(0x05000000),
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
                            color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.verified_user_rounded, color: AppTheme.primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PG Owner: $_payeeName',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: textPri,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'UPI ID: $_ownerUpiId',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSec,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryBlue),
                          tooltip: 'Copy UPI ID',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _ownerUpiId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Owner UPI ID copied!'), duration: Duration(seconds: 2)),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Payment Options Heading
                  Text(
                    'Select Payment Method',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textPri,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Direct bank-to-bank transfer via your preferred UPI application.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: textSec,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Method 1: Google Pay (Copy UPI ID & Open)
                  _buildPaymentMethodTile(
                    title: 'Pay using Google Pay',
                    subtitle: 'Auto-copies UPI ID & opens Google Pay for reliable transfer',
                    brandColor: const Color(0xFF4285F4),
                    iconData: Icons.g_mobiledata_rounded,
                    isIconLetter: true,
                    context: context,
                    onTap: _handleCopyAndOpenGooglePay,
                  ),
                  const SizedBox(height: 12),

                  // Method 2: Dynamic UPI QR Code
                  _buildPaymentMethodTile(
                    title: 'Dynamic UPI QR Code',
                    subtitle: 'Scan to pay with another phone or from gallery',
                    brandColor: const Color(0xFF0F766E),
                    iconData: Icons.qr_code_2_rounded,
                    isIconLetter: false,
                    context: context,
                    onTap: _handleDynamicQrCode,
                  ),
                  const SizedBox(height: 12),

                  // Option 3: Google Pay (Verified Real UPI)
                  _buildPaymentMethodTile(
                    title: 'Google Pay',
                    subtitle: 'Fast, secure UPI transfer to $_payeeName',
                    brandColor: const Color(0xFF4285F4),
                    iconData: Icons.launch_rounded,
                    context: context,
                    onTap: () => _handlePaymentMethodSelection('Google Pay', 'gpay'),
                  ),
                  const SizedBox(height: 12),

                  // Dedicated PhonePe Direct Action (com.phonepe.app)
                  _buildPaymentMethodTile(
                    title: 'Pay using PhonePe',
                    subtitle: 'Direct UPI payment via PhonePe (com.phonepe.app)',
                    brandColor: const Color(0xFF5F259F),
                    iconData: Icons.payments_rounded,
                    context: context,
                    onTap: _handlePhonePePayment,
                  ),
                  const SizedBox(height: 12),

                  // Option 3: Other UPI Apps
                  _buildPaymentMethodTile(
                    title: 'Any Installed UPI App',
                    subtitle: 'Paytm, BHIM, CRED or any bank UPI application',
                    brandColor: const Color(0xFF0284C7),
                    iconData: Icons.account_balance_rounded,
                    context: context,
                    onTap: () => _handlePaymentMethodSelection('Other UPI', 'upi'),
                  ),
                  const SizedBox(height: 12),

                  // Option 4: Demo Online Payment
                  _buildPaymentMethodTile(
                    title: 'Demo Online Payment',
                    subtitle: 'Instant test settlement without external UPI apps',
                    brandColor: const Color(0xFF10B981),
                    iconData: Icons.science_rounded,
                    context: context,
                    onTap: () => _handlePaymentMethodSelection('Demo Pay', 'demo'),
                  ),
                  const SizedBox(height: 22),

                  // Open Payment Interface Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showPaymentInterfaceModal,
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: Text(
                        'Pay ₹ ${_formatAmount(amount)} Now',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                        shadowColor: const Color(0x594F46E5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Security Assurance
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.shield_rounded, color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF16A34A), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '100% Encrypted & Bank-Verified. Recipient: $_payeeName ($defaultCurrency).',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodTile({
    required String title,
    required String subtitle,
    required Color brandColor,
    required IconData iconData,
    bool isIconLetter = false,
    required VoidCallback onTap,
    BuildContext? context,
  }) {
    final isDark = context != null ? AppTheme.isDark(context) : false;
    final cardBg = context != null ? AppTheme.cardBg(context) : Colors.white;
    final borderCol = context != null ? AppTheme.borderCol(context) : const Color(0xFFE2E8F0);
    final textPri = context != null ? AppTheme.textPrimary(context) : AppTheme.textDark;
    final textSec = context != null ? AppTheme.textSecondary(context) : AppTheme.textGrey;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x1A000000) : const Color(0x08000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isLaunching ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: brandColor.withValues(alpha: 0.25)),
                  ),
                  child: Center(
                    child: Icon(
                      iconData,
                      size: isIconLetter ? 30 : 22,
                      color: brandColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textPri,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: textSec,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
