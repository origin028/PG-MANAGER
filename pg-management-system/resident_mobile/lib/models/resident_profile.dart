class ResidentProfile {
  final String residentId;
  final String userId;
  final String fullName;
  final String phone;
  final String? email;
  final String propertyId;
  final String propertyName;
  final String? propertyAddress;
  final String? roomNumber;
  final String? bedNumber;
  final String checkInDate;
  final double monthlyRent;
  final double securityDeposit;
  final String kycStatus;
  final String status;

  ResidentProfile({
    required this.residentId,
    required this.userId,
    required this.fullName,
    required this.phone,
    this.email,
    required this.propertyId,
    required this.propertyName,
    this.propertyAddress,
    this.roomNumber,
    this.bedNumber,
    required this.checkInDate,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.kycStatus,
    required this.status,
  });

  factory ResidentProfile.fromJson(Map<String, dynamic> json) {
    return ResidentProfile(
      residentId: json['resident_id'] ?? '',
      userId: json['user_id'] ?? '',
      fullName: json['full_name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      propertyId: json['property_id'] ?? '',
      propertyName: json['property_name'] ?? 'Assigned PG',
      propertyAddress: json['property_address'],
      roomNumber: json['room_number'],
      bedNumber: json['bed_number'],
      checkInDate: json['check_in_date'] ?? '',
      monthlyRent: (json['monthly_rent'] as num?)?.toDouble() ?? 0.0,
      securityDeposit: (json['security_deposit'] as num?)?.toDouble() ?? 0.0,
      kycStatus: json['kyc_status'] ?? 'PENDING',
      status: json['status'] ?? 'ACTIVE',
    );
  }
}
