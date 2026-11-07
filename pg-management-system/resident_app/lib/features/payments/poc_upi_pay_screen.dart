import 'package:flutter/material.dart';
import 'package:upi_pay/upi_pay.dart' as upi;
import '../../core/theme/app_theme.dart';
import 'poc_upi_pay_service.dart';

class PocUpiPayScreen extends StatefulWidget {
  final Map<String, dynamic>? invoiceData;

  const PocUpiPayScreen({super.key, this.invoiceData});

  @override
  State<PocUpiPayScreen> createState() => _PocUpiPayScreenState();
}

class _PocUpiPayScreenState extends State<PocUpiPayScreen> {
  bool _isDiscovering = false;
  bool _isExecuting = false;
  bool _enablePhonePeFallback = true;
  List<PocDiscoveredApp> _discoveredApps = [];
  PocUpiPayExecutionResult? _lastResult;

  late final String _invoiceId;
  late final double _amount;

  @override
  void initState() {
    super.initState();
    _invoiceId = widget.invoiceData?['id']?.toString() ?? 'INV-2026-TEST';
    // Strictly force ₹1.00 for test safety
    _amount = 1.00;
    _runDiscovery();
  }

  Future<void> _runDiscovery() async {
    setState(() => _isDiscovering = true);
    try {
      final apps = await PocUpiPayService.discoverInstalledApps();
      if (mounted) {
        setState(() {
          _discoveredApps = apps;
          _isDiscovering = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isDiscovering = false);
    }
  }

  Future<void> _executePayment({
    required String appName,
    required String packageName,
    required upi.UpiApplication upiApp,
  }) async {
    if (_isExecuting) return;
    setState(() {
      _isExecuting = true;
      _lastResult = null;
    });

    try {
      final res = await PocUpiPayService.initiatePocPayment(
        appName: appName,
        packageName: packageName,
        upiApp: upiApp,
        invoiceId: _invoiceId,
        amount: _amount,
        enableNativePhonePeFallback: _enablePhonePeFallback,
      );

      if (mounted) {
        setState(() {
          _lastResult = res;
          _isExecuting = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgCol = AppTheme.pageBg(context);
    final cardBg = AppTheme.cardBg(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final borderCol = AppTheme.borderCol(context);

    return Scaffold(
      backgroundColor: bgCol,
      appBar: AppBar(
        title: const Text('upi_pay Package Evaluation POC'),
        centerTitle: false,
        backgroundColor: cardBg,
        foregroundColor: textPri,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isDiscovering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Re-run App Discovery',
            onPressed: _isDiscovering ? null : _runDiscovery,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Safe Test Invoice Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFF0D9488), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Invoice: $_invoiceId (₹${_amount.toStringAsFixed(2)})',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textPri,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Payee: ${PocUpiPayService.verifiedPayeeName} (${PocUpiPayService.verifiedPayeeVpa})',
                          style: TextStyle(fontSize: 12, color: textSec),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Strict Safety: State remains PENDING_VERIFICATION (Never auto-marked PAID).',
                          style: TextStyle(fontSize: 11, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Package Compatibility & Architecture Notes
            Text(
              'Package Evaluation Diagnostics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPri),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBulletPoint(
                    'Target Package:',
                    'upi_pay: ^1.1.0 (drenther/upi_pay, discontinued on pub.dev)',
                    textPri,
                    textSec,
                  ),
                  const SizedBox(height: 6),
                  _buildBulletPoint(
                    'Discovery Mode:',
                    'UpiApplicationDiscoveryAppStatusType.all (Bypasses hardcoded fail status)',
                    textPri,
                    textSec,
                  ),
                  const SizedBox(height: 6),
                  _buildBulletPoint(
                    'Navi UPI Support:',
                    'Handled via custom UpiApplication (Missing from native upi_pay enum)',
                    textPri,
                    textSec,
                  ),
                  const SizedBox(height: 6),
                  _buildBulletPoint(
                    'Native Channel Coexistence:',
                    'upi_pay channel "upi_pay" coexists with app channel "com.originpg.resident/native_upi"',
                    textPri,
                    textSec,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Discovered Apps Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discovered UPI Apps (${_discoveredApps.length})',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPri),
                ),
                TextButton.icon(
                  onPressed: _isDiscovering ? null : _runDiscovery,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_discoveredApps.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderCol),
                ),
                child: Text(
                  _isDiscovering
                      ? 'Querying PackageManager via upi_pay...'
                      : 'No UPI apps discovered via standard upi://pay query.',
                  style: TextStyle(color: textSec, fontSize: 13),
                ),
              )
            else
              ...List.generate(_discoveredApps.length, (idx) {
                final app = _discoveredApps[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    children: [
                      _buildAppIcon(app),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.appName,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPri),
                            ),
                            Text(
                              app.packageName,
                              style: TextStyle(fontSize: 11, color: textSec),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: app.isNativelySupportedByPackage
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          app.isNativelySupportedByPackage ? 'In Enum' : 'Custom App',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: app.isNativelySupportedByPackage ? Colors.green : Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 20),

            // Independent Testing Action Tiles
            Text(
              'Execute Isolated upi_pay Test Launches',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPri),
            ),
            const SizedBox(height: 8),

            // 1. Google Pay Tile
            _buildTestTile(
              title: '1. Test Google Pay via upi_pay',
              subtitle: 'Launches com.google.android.apps.nbu.paisa.user via startActivityForResult',
              icon: Icons.payment,
              iconColor: Colors.blue,
              cardBg: cardBg,
              borderCol: borderCol,
              textPri: textPri,
              textSec: textSec,
              onTap: () => _executePayment(
                appName: 'Google Pay',
                packageName: PocUpiPayService.googlePayPackage,
                upiApp: upi.UpiApplication.googlePay,
              ),
            ),
            const SizedBox(height: 8),

            // 2. PhonePe Tile
            _buildTestTile(
              title: '2. Test PhonePe via upi_pay',
              subtitle: 'Launches com.phonepe.app via upi_pay (with native fallback toggle)',
              icon: Icons.phone_android,
              iconColor: const Color(0xFF5F259F),
              cardBg: cardBg,
              borderCol: borderCol,
              textPri: textPri,
              textSec: textSec,
              extraWidget: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enable Native Kotlin 4-tier Fallback if upi_pay fails',
                  style: TextStyle(fontSize: 12, color: textPri),
                ),
                value: _enablePhonePeFallback,
                onChanged: (val) => setState(() => _enablePhonePeFallback = val),
              ),
              onTap: () => _executePayment(
                appName: 'PhonePe',
                packageName: PocUpiPayService.phonePePackage,
                upiApp: upi.UpiApplication.phonePe,
              ),
            ),
            const SizedBox(height: 8),

            // 3. Navi Tile
            _buildTestTile(
              title: '3. Test Navi UPI via Custom upi_pay App',
              subtitle: 'Launches Navi (com.naviapp / com.navi.curiosity) using custom UpiApplication',
              icon: Icons.navigation,
              iconColor: Colors.teal,
              cardBg: cardBg,
              borderCol: borderCol,
              textPri: textPri,
              textSec: textSec,
              onTap: () {
                final discoveredNavi = _discoveredApps.cast<PocDiscoveredApp?>().firstWhere(
                  (a) =>
                      a != null &&
                      (a.packageName == PocUpiPayService.naviPackage ||
                          a.packageName == PocUpiPayService.naviAppPackage),
                  orElse: () => null,
                );
                final targetPkg =
                    discoveredNavi?.packageName ?? PocUpiPayService.naviPackage;
                final targetApp =
                    discoveredNavi?.upiApplication ?? PocUpiPayService.naviCustomApplication;

                _executePayment(
                  appName: 'Navi UPI',
                  packageName: targetPkg,
                  upiApp: targetApp,
                );
              },
            ),
            const SizedBox(height: 20),

            // Execution Result Card
            if (_isExecuting)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Executing upi_pay.initiateTransaction...',
                        style: TextStyle(fontSize: 13, color: textSec),
                      ),
                    ],
                  ),
                ),
              )
            else if (_lastResult != null)
              _buildResultCard(_lastResult!, cardBg, borderCol, textPri, textSec),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIcon(PocDiscoveredApp app) {
    if (app.rawMeta != null &&
        (Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS)) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: app.rawMeta!.iconImage(36),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
      child: const Icon(Icons.account_balance_wallet, size: 20, color: Color(0xFF6366F1)),
    );
  }

  Widget _buildBulletPoint(String label, String value, Color textPri, Color textSec) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPri),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: textSec),
          ),
        ),
      ],
    );
  }

  Widget _buildTestTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color cardBg,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    Widget? extraWidget,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: iconColor.withValues(alpha: 0.1),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPri),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: textSec),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _isExecuting ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Test ₹1'),
                ),
              ],
            ),
            if (extraWidget != null) ...[
              const Divider(height: 16),
              extraWidget,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(
    PocUpiPayExecutionResult res,
    Color cardBg,
    Color borderCol,
    Color textPri,
    Color textSec,
  ) {
    final statusColor = res.launched ? Colors.green : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Execution Result: ${res.appName}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPri),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  res.launched ? 'LAUNCHED' : 'NOT RESOLVED',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(res.message, style: TextStyle(fontSize: 13, color: textPri)),
          const Divider(height: 16),

          // Security Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_clock, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'State: PENDING_VERIFICATION (Invoice not marked paid on callback)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Diagnostic Attributes Table
          _buildDetailRow('Target Package', res.packageName, textPri, textSec),
          _buildDetailRow('Txn Ref (tr)', res.txnRef, textPri, textSec),
          _buildDetailRow('Amount', '₹${res.amount.toStringAsFixed(2)}', textPri, textSec),
          _buildDetailRow('Status Enum', res.status?.toString() ?? 'None', textPri, textSec),
          _buildDetailRow('Raw Response', res.rawResponse ?? 'None', textPri, textSec),
          _buildDetailRow('Response Code', res.responseCode ?? 'None', textPri, textSec),
          _buildDetailRow('Approval Ref', res.approvalRefNo ?? 'None', textPri, textSec),
          _buildDetailRow('Txn ID', res.txnId ?? 'None', textPri, textSec),

          const Divider(height: 20),
          Text(
            'Raw Execution Logs:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPri),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              res.diagnosticLogs.join('\n'),
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color textPri, Color textSec) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 11, color: textSec)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textPri),
            ),
          ),
        ],
      ),
    );
  }
}
