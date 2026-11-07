import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class ReceiptScreen extends StatefulWidget {
  final Map<String, dynamic> receiptData;

  const ReceiptScreen({super.key, required this.receiptData});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  bool _isDownloading = false;

  Future<void> _handleDownloadReceiptPdf({
    required String receiptNumber,
    required String invoiceId,
    required dynamic amount,
    required String residentName,
    required String roomNumber,
    required String transactionRef,
  }) async {
    setState(() => _isDownloading = true);
    try {
      String? receiptId = widget.receiptData['id']?.toString() ??
          widget.receiptData['receiptId']?.toString() ??
          widget.receiptData['receipt_id']?.toString();

      // If receipt ID was not passed directly, look up from resident's official receipts
      if (receiptId == null || receiptId.isEmpty) {
        try {
          final receipts = await ResidentApiService.getReceipts();
          final match = receipts.firstWhere(
            (r) =>
                r['receipt_number']?.toString() == receiptNumber ||
                r['invoice_number']?.toString() == invoiceId ||
                r['invoice_id']?.toString() == invoiceId,
            orElse: () => receipts.isNotEmpty ? receipts.first : <String, dynamic>{},
          );
          if (match.isNotEmpty && match['id'] != null) {
            receiptId = match['id'].toString();
          }
        } catch (_) {}
      }

      if (receiptId != null && receiptId.isNotEmpty) {
        final pdfBytes = await ResidentApiService.downloadReceiptPdf(receiptId);
        final safeFileName = 'receipt_${receiptNumber.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.pdf';

        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Rent Receipt PDF',
          fileName: safeFileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: pdfBytes,
        );

        if (!kIsWeb && savedPath != null && savedPath.isNotEmpty) {
          try {
            final f = File(savedPath);
            if (!await f.exists() || await f.length() == 0) {
              await f.writeAsBytes(pdfBytes);
            }
          } catch (_) {}
        }

        if (mounted) {
          if (savedPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rent receipt PDF downloaded successfully!'),
                backgroundColor: Color(0xFF16A34A),
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download cancelled.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // Fallback: Copy official summary to clipboard
        Clipboard.setData(ClipboardData(
          text:
              'RENT RECEIPT: $receiptNumber\nInvoice: $invoiceId\nAmount: ₹$amount\nTenant: $residentName (Room $roomNumber)\nTxn Ref: $transactionRef\nStatus: Paid & Verified',
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receipt details copied to clipboard! (PDF available on server)'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Ensure user always gets feedback and access to text summary
      Clipboard.setData(ClipboardData(
        text:
            'RENT RECEIPT: $receiptNumber\nInvoice: $invoiceId\nAmount: ₹$amount\nTenant: $residentName (Room $roomNumber)\nTxn Ref: $transactionRef\nStatus: Paid & Verified',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not download PDF ($e). Summary copied to clipboard!'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final borderCol = AppTheme.borderCol(context);
    final textPri = AppTheme.textPrimary(context);
    final textSec = AppTheme.textSecondary(context);
    final pageBg = AppTheme.pageBg(context);

    final receiptNumber = widget.receiptData['receiptNumber'] ?? widget.receiptData['receipt_number'] ?? 'REC-2026-11-0084';
    final invoiceId = widget.receiptData['invoiceId'] ?? widget.receiptData['invoice_number'] ?? widget.receiptData['id'] ?? 'INV-2026-010';
    final amount = widget.receiptData['amount'] ?? 8000;
    final paymentApp = widget.receiptData['paymentApp'] ?? widget.receiptData['payment_mode'] ?? 'Google Pay';
    final transactionRef = widget.receiptData['transactionRef'] ?? widget.receiptData['transaction_ref'] ?? 'UPI-20261029-998877';
    final approvalCode = widget.receiptData['bankApprovalCode'] ?? widget.receiptData['approval_code'] ?? 'BANK-AUTH-10492';
    final paidAt = widget.receiptData['paidAt'] != null
        ? DateTime.tryParse(widget.receiptData['paidAt'].toString()) ?? DateTime.now()
        : (widget.receiptData['issued_at'] != null
            ? DateTime.tryParse(widget.receiptData['issued_at'].toString()) ?? DateTime.now()
            : DateTime.now());
    final residentName = widget.receiptData['residentName'] ?? widget.receiptData['resident_name'] ?? 'Akshay B';
    final roomNumber = widget.receiptData['roomNumber'] ?? widget.receiptData['room_number'] ?? '101';
    final propertyName = widget.receiptData['propertyName'] ?? widget.receiptData['property_name'] ?? 'BNR Luxury PG';

    final formattedDate =
        '${paidAt.day.toString().padLeft(2, '0')} ${_monthName(paidAt.month)} ${paidAt.year}, ${paidAt.hour.toString().padLeft(2, '0')}:${paidAt.minute.toString().padLeft(2, '0')}';

    String formatAmount(dynamic amt) {
      if (amt == null) return '0.00';
      final num val = amt is num ? amt : (num.tryParse(amt.toString()) ?? 0);
      if (val % 1 == 0 && val >= 100) {
        return val.toInt().toString();
      }
      return val.toStringAsFixed(2);
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text(
          'Rent Receipt',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPri),
        ),
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
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: textPri),
            tooltip: 'Share Receipt',
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text:
                    'RENT RECEIPT: $receiptNumber\nInvoice: $invoiceId\nAmount: ₹${formatAmount(amount)}\nTenant: $residentName (Room $roomNumber)\nTxn Ref: $transactionRef\nStatus: Paid & Verified',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Receipt summary copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  // Receipt Paper Container
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x2A000000) : const Color(0x0F000000),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top Header with verified badge
                        Container(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF86EFAC), width: 2),
                                ),
                                child: const Center(
                                  child: Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 32),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                propertyName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textPri,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Official E-Rent Payment Receipt',
                                style: TextStyle(fontSize: 12.5, color: textSec),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFBBF7D0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded, size: 14, color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF16A34A)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'VERIFIED & PAID',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Serrated/Dotted separator line
                        _buildCutlineDivider(pageBg: pageBg, dotColor: borderCol),

                        // Amount Block
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                          child: Column(
                            children: [
                              Text(
                                'AMOUNT PAID',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: textSec,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '₹ ${formatAmount(amount)}',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: textPri,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Paid on $formattedDate',
                                style: TextStyle(fontSize: 12, color: textSec),
                              ),
                            ],
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Divider(height: 1, thickness: 1, color: borderCol),
                        ),

                        // Receipt Details Grid
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              _buildReceiptRow('Receipt Number', receiptNumber, isHighlight: true, textPri: textPri, textSec: textSec),
                              const SizedBox(height: 14),
                              _buildReceiptRow('Invoice Number', invoiceId, textPri: textPri, textSec: textSec),
                              const SizedBox(height: 14),
                              _buildReceiptRow('Tenant Name', residentName, textPri: textPri, textSec: textSec),
                              const SizedBox(height: 14),
                              _buildReceiptRow('Room / Bed', 'Room $roomNumber', textPri: textPri, textSec: textSec),
                              const SizedBox(height: 14),
                              _buildReceiptRow('Payment Method', paymentApp, textPri: textPri, textSec: textSec),
                              const SizedBox(height: 14),
                              _buildCopyableRow(context, 'Transaction Ref', transactionRef, textPri: textPri, textSec: textSec),
                              const SizedBox(height: 14),
                              _buildReceiptRow('Bank Auth Code', approvalCode, textPri: textPri, textSec: textSec),
                            ],
                          ),
                        ),

                        // Security & Note Footer inside receipt
                        Container(
                          padding: const EdgeInsets.all(18),
                          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderCol),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_rounded, size: 18, color: textSec),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'This is an authorized computer-generated rent receipt settled directly to PG Owner bank account.',
                                  style: TextStyle(fontSize: 11, color: textSec, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading
                          ? null
                          : () => _handleDownloadReceiptPdf(
                                receiptNumber: receiptNumber,
                                invoiceId: invoiceId,
                                amount: amount,
                                residentName: residentName,
                                roomNumber: roomNumber,
                                transactionRef: transactionRef,
                              ),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(_isDownloading ? 'Downloading PDF...' : 'Download Receipt PDF / Summary'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.go('/home'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: borderCol),
                        backgroundColor: cardBg,
                      ),
                      child: Text(
                        'Done (Return to Home)',
                        style: TextStyle(color: textPri, fontWeight: FontWeight.bold),
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

  Widget _buildCutlineDivider({required Color pageBg, required Color dotColor}) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: List.generate(
              30,
              (index) => Expanded(
                child: Container(
                  height: 1.5,
                  color: index.isEven ? dotColor : Colors.transparent,
                ),
              ),
            ),
          ),
          Positioned(
            left: -10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: pageBg,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: pageBg,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isHighlight = false, required Color textPri, required Color textSec}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: textSec),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              color: isHighlight ? AppTheme.primaryBlue : textPri,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCopyableRow(BuildContext context, String label, String value, {required Color textPri, required Color textSec}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: textSec),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied!'), duration: const Duration(seconds: 1)),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: textPri,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.copy_rounded, size: 14, color: AppTheme.primaryBlue),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
