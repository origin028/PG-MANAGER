class ReceiptSummary {
  final String id;
  final String receiptNumber;
  final double amount;
  final String issuedAt;
  final String invoiceId;
  final String invoiceNumber;
  final String billingMonth;
  final String paymentMode;

  ReceiptSummary({
    required this.id,
    required this.receiptNumber,
    required this.amount,
    required this.issuedAt,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.billingMonth,
    required this.paymentMode,
  });

  factory ReceiptSummary.fromJson(Map<String, dynamic> json) {
    return ReceiptSummary(
      id: json['id'] ?? '',
      receiptNumber: json['receipt_number'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      issuedAt: json['issued_at'] ?? '',
      invoiceId: json['invoice_id'] ?? '',
      invoiceNumber: json['invoice_number'] ?? '',
      billingMonth: json['billing_month'] ?? '',
      paymentMode: json['payment_mode'] ?? 'UPI',
    );
  }
}

class ReceiptDetail {
  final String id;
  final String receiptNumber;
  final double amount;
  final String issuedAt;
  final String invoiceId;
  final String invoiceNumber;
  final String billingMonth;
  final String invoiceType;
  final String propertyName;
  final String? propertyAddress;
  final String? roomNumber;
  final String? bedNumber;
  final String residentId;
  final String residentName;
  final String residentPhone;
  final String? residentEmail;
  final String paymentId;
  final String paymentNumber;
  final String paymentMode;
  final String? gatewayPaymentId;
  final String? paidAt;

  ReceiptDetail({
    required this.id,
    required this.receiptNumber,
    required this.amount,
    required this.issuedAt,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.billingMonth,
    required this.invoiceType,
    required this.propertyName,
    this.propertyAddress,
    this.roomNumber,
    this.bedNumber,
    required this.residentId,
    required this.residentName,
    required this.residentPhone,
    this.residentEmail,
    required this.paymentId,
    required this.paymentNumber,
    required this.paymentMode,
    this.gatewayPaymentId,
    this.paidAt,
  });

  factory ReceiptDetail.fromJson(Map<String, dynamic> json) {
    return ReceiptDetail(
      id: json['id'] ?? '',
      receiptNumber: json['receipt_number'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      issuedAt: json['issued_at'] ?? '',
      invoiceId: json['invoice_id'] ?? '',
      invoiceNumber: json['invoice_number'] ?? '',
      billingMonth: json['billing_month'] ?? '',
      invoiceType: json['invoice_type'] ?? 'RENT',
      propertyName: json['property_name'] ?? 'Origin PG',
      propertyAddress: json['property_address'],
      roomNumber: json['room_number'],
      bedNumber: json['bed_number'],
      residentId: json['resident_id'] ?? '',
      residentName: json['resident_name'] ?? 'Resident',
      residentPhone: json['resident_phone'] ?? '',
      residentEmail: json['resident_email'],
      paymentId: json['payment_id'] ?? '',
      paymentNumber: json['payment_number'] ?? '',
      paymentMode: json['payment_mode'] ?? 'UPI',
      gatewayPaymentId: json['gateway_payment_id'],
      paidAt: json['paid_at'],
    );
  }
}
