class User {
  final String id;
  final String fullName;
  final String? email;
  final String phone;
  final String roleName;

  User({
    required this.id,
    required this.fullName,
    this.email,
    required this.phone,
    required this.roleName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      fullName: json['full_name'] ?? '',
      email: json['email'],
      phone: json['phone'] ?? '',
      roleName: json['role']?['name'] ?? '',
    );
  }
}
