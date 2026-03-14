// models/user_model.dart
class UserModel {
  final String id;
  final String name;
  final String? email;
  final String? photoUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? role;
  final String? phone;

  UserModel({
    required this.id,
    required this.name,
    this.email,
    this.photoUrl,
    this.isOnline = false,
    this.lastSeen,
    this.role,
    this.phone,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? json['full_name'] ?? '',
      email: json['email'],
      photoUrl: json['profile_photo_url'] ?? json['photo_url'],
      isOnline: json['is_online'] == true,
      lastSeen: json['last_seen'] != null 
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,
      role: json['role'],
      phone: json['phone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profile_photo_url': photoUrl,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'role': role,
      'phone': phone,
    };
  }
}