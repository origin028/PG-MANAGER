class PaymentRequestResponse {
  final String paymentId;
  final String paymentNumber;
  final String gatewayOrderId;
  final double amount;
  final int amountPaise;
  final String currency;
  final String keyId;
  final String? propertyName;
  final String? description;
  final String? residentName;
  final String? residentPhone;
  final String? residentEmail;

  PaymentRequestResponse({
    required this.paymentId,
    required this.paymentNumber,
    required this.gatewayOrderId,
    required this.amount,
    required this.amountPaise,
    this.currency = 'INR',
    required this.keyId,
    this.propertyName,
    this.description,
    this.residentName,
    this.residentPhone,
    this.residentEmail,
  });

  factory PaymentRequestResponse.fromJson(Map<String, dynamic> json) {
    return PaymentRequestResponse(
      paymentId: json['payment_id'] ?? '',
      paymentNumber: json['payment_number'] ?? '',
      gatewayOrderId: json['gateway_order_id'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      amountPaise: (json['amount_paise'] as num?)?.toInt() ?? 0,
      currency: json['currency'] ?? 'INR',
      keyId: json['key_id'] ?? '',
      propertyName: json['property_name'],
      description: json['description'],
      residentName: json['resident_name'],
      residentPhone: json['resident_phone'],
      residentEmail: json['resident_email'],
    );
  }
}

class PaymentStatus {
  final String paymentId;
  final String paymentNumber;
  final String invoiceId;
  final double amount;
  final String status; // PENDING, SUCCESS, FAILED
  final String paymentMode;
  final String? gatewayOrderId;
  final String? gatewayPaymentId;
  final String? paidAt;
  final bool isSettled;
  final String? receiptId;
  final String? receiptNumber;

  PaymentStatus({
    required this.paymentId,
    required this.paymentNumber,
    required this.invoiceId,
    required this.amount,
    required this.status,
    required this.paymentMode,
    this.gatewayOrderId,
    this.gatewayPaymentId,
    this.paidAt,
    required this.isSettled,
    this.receiptId,
    this.receiptNumber,
  });

  bool get isSuccess => status == 'SUCCESS';
  bool get isPending => status == 'PENDING';
  bool get isFailed => status == 'FAILED';

  factory PaymentStatus.fromJson(Map<String, dynamic> json) {
    return PaymentStatus(
      paymentId: json['payment_id'] ?? '',
      paymentNumber: json['payment_number'] ?? '',
      invoiceId: json['invoice_id'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'PENDING',
      paymentMode: json['payment_mode'] ?? 'UPI',
      gatewayOrderId: json['gateway_order_id'],
      gatewayPaymentId: json['gateway_payment_id'],
      paidAt: json['paid_at'],
      isSettled: json['is_settled'] ?? false,
      receiptId: json['receipt_id'],
      receiptNumber: json['receipt_number'],
    );
  }
}
