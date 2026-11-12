import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../core/services/payment_verification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion_wrappers.dart';
import 'receipt_screen.dart';

class PaymentStatusScreen extends StatefulWidget {
  final Map<String, dynamic> paymentData;

  const PaymentStatusScreen({super.key, required this.paymentData});

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  PaymentVerificationState _currentState = PaymentVerificationState.pendingVerification;
  PaymentVerificationResult? _verificationResult;
  Timer? _pollingTimer;
  int _pollCount = 0;
  bool _isManualChecking = false;

  @override
  void initState() {
    super.initState();
    if (widget.paymentData['autoPoll'] != false) {
      _startBackendVerificationPolling();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  String _formatAmount(dynamic amt) {
    if (amt == null) return '0.00';
    final num val = amt is num ? amt : (num.tryParse(amt.toString()) ?? 0);
    if (val % 1 == 0 && val >= 100) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(2);
  }

  void _startBackendVerificationPolling() {
    // Initial verification poll
    _checkStatusWithBackend();

    // Polling every 2.5 seconds
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (_currentState != PaymentVerificationState.pendingVerification) {
        timer.cancel();
        return;
      }
      _checkStatusWithBackend();
    });
  }

  Future<void> _checkStatusWithBackend({bool isManual = false}) async {
    if (_isManualChecking) return;

    if (mounted) {
      setState(() => _isManualChecking = isManual);
    }

    _pollCount++;
    final invoiceId = widget.paymentData['invoiceId']?.toString() ?? 'INV-2026-010';
    final txnRef = widget.paymentData['txnRef']?.toString() ?? 'TXN-998877';
    final paymentApp = widget.paymentData['paymentApp']?.toString() ?? 'Google Pay';
    final num amount = (widget.paymentData['amount'] as num?) ?? 8000;
    final paymentId = widget.paymentData['paymentId']?.toString();

    // After polling simulation, query trusted backend settlement
    final result = await PaymentVerificationService.verifyWithBackend(
      invoiceId: invoiceId,
      txnRef: txnRef,
      paymentApp: paymentApp,
      amount: amount,
      paymentId: paymentId,
    );

    if (!mounted) return;
    if (_currentState == PaymentVerificationState.cancelled ||
        _currentState == PaymentVerificationState.failed) {
      return;
    }

    setState(() {
      _isManualChecking = false;
      _verificationResult = result;
      _currentState = result.state;
    });

    if (result.state != PaymentVerificationState.pendingVerification) {
      _pollingTimer?.cancel();
    }
  }

  Future<void> _simulateSettlementState() async {
    _pollingTimer?.cancel();
    final invoiceId = widget.paymentData['invoiceId']?.toString() ?? 'INV-2026-010';
    final txnRef = widget.paymentData['txnRef']?.toString() ?? 'TXN-998877';
    final paymentApp = widget.paymentData['paymentApp']?.toString() ?? 'Google Pay';
    final amount = (widget.paymentData['amount'] as num?)?.toInt() ?? 8000;

    final res = await PaymentVerificationService.simulateBankSettlement(
      invoiceId: invoiceId,
      txnRef: txnRef,
      paymentApp: paymentApp,
      amount: amount,
    );

    if (mounted) {
      setState(() {
        _verificationResult = res;
        _currentState = PaymentVerificationState.successful;
      });
    }
  }

  Future<void> _simulateFailedState() async {
    _pollingTimer?.cancel();
    final invoiceId = widget.paymentData['invoiceId']?.toString() ?? 'INV-2026-010';
    final txnRef = widget.paymentData['txnRef']?.toString() ?? 'TXN-998877';
    final paymentApp = widget.paymentData['paymentApp']?.toString() ?? 'Google Pay';
    final num amount = (widget.paymentData['amount'] as num?) ?? 8000;

    final res = await PaymentVerificationService.verifyWithBackend(
      invoiceId: invoiceId,
      txnRef: txnRef,
      paymentApp: paymentApp,
      amount: amount,
      forceFail: true,
    );

    if (mounted) {
      setState(() {
        _verificationResult = res;
        _currentState = PaymentVerificationState.failed;
      });
    }
  }

  Future<void> _simulateCancelledState() async {
    _pollingTimer?.cancel();
    final invoiceId = widget.paymentData['invoiceId']?.toString() ?? 'INV-2026-010';
    final txnRef = widget.paymentData['txnRef']?.toString() ?? 'TXN-998877';
    final paymentApp = widget.paymentData['paymentApp']?.toString() ?? 'Google Pay';
    final num amount = (widget.paymentData['amount'] as num?) ?? 8000;
    final paymentId = widget.paymentData['paymentId']?.toString();

    final res = await PaymentVerificationService.cancelPayment(
      invoiceId: invoiceId,
      txnRef: txnRef,
      paymentApp: paymentApp,
      amount: amount,
      paymentId: paymentId,
    );

    if (mounted) {
      setState(() {
        _verificationResult = res;
        _currentState = PaymentVerificationState.cancelled;
      });
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final cardBg = AppTheme.cardBg(context);
    final textPri = AppTheme.textPrimary(context);
    final pageBg = AppTheme.pageBg(context);

    return PopScope(
      canPop: _currentState != PaymentVerificationState.pendingVerification,
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          title: Text(
            'Payment Status',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPri),
          ),
          backgroundColor: cardBg,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            if (_currentState != PaymentVerificationState.pendingVerification)
              IconButton(
                icon: Icon(Icons.close_rounded, color: textPri),
                onPressed: () => context.go('/home'),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: AnimatedSwitcher(
                  duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_currentState),
                    child: _buildCurrentStateView(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStateView() {
    switch (_currentState) {
      case PaymentVerificationState.pendingVerification:
        return _buildPendingVerificationView();
      case PaymentVerificationState.successful:
        return _buildSuccessfulView();
      case PaymentVerificationState.failed:
        return _buildFailedView();
      case PaymentVerificationState.cancelled:
        return _buildCancelledView();
    }
  }

  // 1. Pending Verification State
  Widget _buildPendingVerificationView() {
    final invoiceId = widget.paymentData['invoiceId'] ?? 'INV-2026-010';
    final txnRef = widget.paymentData['txnRef'] ?? 'TXN-998877';
    final amount = widget.paymentData['amount'] ?? 8000;
    final paymentApp = widget.paymentData['paymentApp'] ?? 'UPI';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
            ),
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: AppTheme.primaryBlue,
              ),
            ),
            const Icon(Icons.hourglass_top_rounded, color: AppTheme.primaryBlue, size: 28),
          ],
        ),
        const SizedBox(height: 24),

        const Text(
          'Payment Pending Verification',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your transaction is awaiting trusted confirmation from your bank and the PG Owner account.',
          style: TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Polling Indicator Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 8),
              Text(
                'Checking backend status (Attempt $_pollCount)...',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Payment Summary Box
        _buildTransactionDetailsCard(
          invoiceId: invoiceId,
          txnRef: txnRef,
          amount: amount,
          paymentApp: paymentApp,
          payeeName: PaymentVerificationService.verifiedPayeeName,
          payeeUpiId: PaymentVerificationService.verifiedPayeeUpiId,
          statusText: 'Pending Bank Confirmation',
          statusColor: const Color(0xFFD97706),
        ),
        const SizedBox(height: 28),

        // Action Buttons
        MotionEntrance(
          delay: const Duration(milliseconds: 90),
          child: TactilePress(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isManualChecking ? null : () => _checkStatusWithBackend(isManual: true),
                icon: _isManualChecking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_isManualChecking ? 'Querying Backend...' : 'Refresh Status'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TactilePress(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _simulateCancelledState(),
              icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
              label: const Text('Cancel Payment Attempt', style: TextStyle(color: Color(0xFF64748B))),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Testing Simulation Options
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            TextButton(
              onPressed: _simulateSettlementState,
              child: const Text('Simulate Settlement', style: TextStyle(fontSize: 12, color: Color(0xFF16A34A))),
            ),
            const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
            TextButton(
              onPressed: _simulateCancelledState,
              child: const Text('Simulate Cancelled', style: TextStyle(fontSize: 12, color: Color(0xFFD97706))),
            ),
            const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
            TextButton(
              onPressed: _simulateFailedState,
              child: const Text('Simulate Failed', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
            ),
          ],
        ),
      ],
    );
  }

  // 2. Successful Payment State
  Widget _buildSuccessfulView() {
    final invoiceId = _verificationResult?.invoiceId ?? widget.paymentData['invoiceId'] ?? 'INV-2026-010';
    final txnRef = _verificationResult?.transactionRef ?? widget.paymentData['txnRef'] ?? 'TXN-998877';
    final amount = _verificationResult?.amount ?? widget.paymentData['amount'] ?? 8000;
    final paymentApp = _verificationResult?.paymentApp ?? widget.paymentData['paymentApp'] ?? 'Google Pay';
    final approvalCode = _verificationResult?.bankApprovalCode ?? 'BANK-AUTH-88219';
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF86EFAC), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0x264CAF50),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Lottie.asset(
              'assets/animations/payment_success.json',
              width: 64,
              height: 64,
              repeat: false,
              animate: !disableAnim,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 54,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        MotionEntrance(
          delay: const Duration(milliseconds: 80),
          child: Column(
            children: [
              const Text(
                'Payment Successful!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'Confirmed and settled with Property Owner backend.',
                style: TextStyle(fontSize: 13, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Amount Badge
        MotionEntrance(
          delay: const Duration(milliseconds: 140),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Text(
              '₹ ${_formatAmount(amount)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Color(0xFF15803D),
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Details Card
        MotionEntrance(
          delay: const Duration(milliseconds: 190),
          child: _buildTransactionDetailsCard(
            invoiceId: invoiceId,
            txnRef: txnRef,
            amount: amount,
            paymentApp: paymentApp,
            payeeName: PaymentVerificationService.verifiedPayeeName,
            payeeUpiId: PaymentVerificationService.verifiedPayeeUpiId,
            statusText: 'Verified & Settled',
            statusColor: const Color(0xFF16A34A),
            approvalCode: approvalCode,
          ),
        ),
        const SizedBox(height: 28),

        // Action Buttons
        MotionEntrance(
          delay: const Duration(milliseconds: 240),
          child: Column(
            children: [
              TactilePress(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => ReceiptScreen(
                            receiptData: _verificationResult?.receiptData ?? {
                              'receiptNumber': 'REC-2026-11-0084',
                              'invoiceId': invoiceId,
                              'amount': amount,
                              'paymentApp': paymentApp,
                              'transactionRef': txnRef,
                              'bankApprovalCode': approvalCode,
                              'paidAt': DateTime.now().toIso8601String(),
                              'residentName': 'Resident',
                              'roomNumber': '101',
                              'propertyName': 'BNR Luxury PG',
                              'status': 'Verified & Settled',
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('View Digital Receipt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TactilePress(
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/home'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: const Text('Back to Home Screen', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. Failed State
  Widget _buildFailedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
          ),
          child: const Center(
            child: Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 54),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Payment Failed',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your bank could not complete the transaction or verification timed out. Any deducted funds will be reversed within 24 hours.',
          style: TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        MotionEntrance(
          delay: const Duration(milliseconds: 90),
          child: TactilePress(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Retry Payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/home'),
          child: const Text('Return to Home', style: TextStyle(color: AppTheme.textGrey)),
        ),
      ],
    );
  }

  // 4. Cancelled State
  Widget _buildCancelledView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCD34D), width: 2),
          ),
          child: const Center(
            child: Icon(Icons.error_outline_rounded, color: Color(0xFFD97706), size: 54),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Payment Cancelled',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 8),
        const Text(
          'The payment was cancelled in the UPI application before approval.',
          style: TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        MotionEntrance(
          delay: const Duration(milliseconds: 90),
          child: TactilePress(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Choose Another Payment Option'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/home'),
          child: const Text('Return to Home', style: TextStyle(color: AppTheme.textGrey)),
        ),
      ],
    );
  }

  Widget _buildTransactionDetailsCard({
    required String invoiceId,
    required String txnRef,
    required num amount,
    required String paymentApp,
    String payeeName = "Saukatali Masi",
    String payeeUpiId = 'masisokatali90900@okaxis',
    required String statusText,
    required Color statusColor,
    String? approvalCode,
  }) {
    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final borderCol = AppTheme.borderCol(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x1A000000) : const Color(0x05000000),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDetailRow('Payee Name', payeeName),
          Divider(height: 18, color: borderCol),
          _buildDetailRow('Payee UPI ID', payeeUpiId),
          Divider(height: 18, color: borderCol),
          _buildDetailRow('Invoice ID', invoiceId),
          Divider(height: 18, color: borderCol),
          _buildDetailRow('Payment App', paymentApp),
          Divider(height: 18, color: borderCol),
          _buildDetailRow('Transaction Ref', txnRef),
          Divider(height: 18, color: borderCol),
          _buildDetailRow('Amount', '₹ ${_formatAmount(amount)}', isBold: true),
          if (approvalCode != null) ...[
            Divider(height: 18, color: borderCol),
            _buildDetailRow('Bank Approval', approvalCode),
          ],
          Divider(height: 18, color: borderCol),
          _buildDetailRow('Status', statusText, valueColor: statusColor, isBold: true),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: textSec)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? textPri,
            ),
          ),
        ),
      ],
    );
  }
}
