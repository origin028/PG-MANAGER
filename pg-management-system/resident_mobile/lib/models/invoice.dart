class ResidentInvoiceItem {
  final String id;
  final String invoiceNumber;
  final String billingMonth;
  final String invoiceType;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String dueDate;
  final String status;
  final String? notes;
  final String createdAt;

  ResidentInvoiceItem({
    required this.id,
    required this.invoiceNumber,
    required this.billingMonth,
    required this.invoiceType,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.dueDate,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  bool get isPaid => status == 'PAID';
  bool get isPending => status == 'PENDING';
  bool get isPartiallyPaid => status == 'PARTIALLY_PAID';
  bool get isOverdue => status == 'OVERDUE';

  factory ResidentInvoiceItem.fromJson(Map<String, dynamic> json) {
    return ResidentInvoiceItem(
      id: json['id'] ?? '',
      invoiceNumber: json['invoice_number'] ?? '',
      billingMonth: json['billing_month'] ?? '',
      invoiceType: json['invoice_type'] ?? 'RENT',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (json['remaining_amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: json['due_date'] ?? '',
      status: json['status'] ?? 'PENDING',
      notes: json['notes'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

class ResidentInvoiceDetail {
  final String id;
  final String propertyId;
  final String propertyName;
  final String residentId;
  final String residentName;
  final String invoiceNumber;
  final String billingMonth;
  final String invoiceType;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String dueDate;
  final String status;
  final String? notes;
  final String createdAt;
  final String? receiptId;
  final String? receiptNumber;
  final String? gatewayOrderId;
  final String? paidAt;

  ResidentInvoiceDetail({
    required this.id,
    required this.propertyId,
    required this.propertyName,
    required this.residentId,
    required this.residentName,
    required this.invoiceNumber,
    required this.billingMonth,
    required this.invoiceType,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.dueDate,
    required this.status,
    this.notes,
    required this.createdAt,
    this.receiptId,
    this.receiptNumber,
    this.gatewayOrderId,
    this.paidAt,
  });

  bool get isPaid => status == 'PAID';

  factory ResidentInvoiceDetail.fromJson(Map<String, dynamic> json) {
    return ResidentInvoiceDetail(
      id: json['id'] ?? '',
      propertyId: json['property_id'] ?? '',
      propertyName: json['property_name'] ?? '',
      residentId: json['resident_id'] ?? '',
      residentName: json['resident_name'] ?? '',
      invoiceNumber: json['invoice_number'] ?? '',
      billingMonth: json['billing_month'] ?? '',
      invoiceType: json['invoice_type'] ?? 'RENT',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (json['remaining_amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: json['due_date'] ?? '',
      status: json['status'] ?? 'PENDING',
      notes: json['notes'],
      createdAt: json['created_at'] ?? '',
      receiptId: json['receipt_id'],
      receiptNumber: json['receipt_number'],
      gatewayOrderId: json['gateway_order_id'],
      paidAt: json['paid_at'],
    );
  }
}
