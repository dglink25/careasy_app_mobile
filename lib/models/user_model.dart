// lib/models/user_model.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTIONS:
// 1. Lit 'last_seen_at' ET 'last_seen' (le backend envoie last_seen_at)
// 2. Calcule isOnline côté Flutter: dernière activité < 5 minutes
// 3. Convertit last_seen en heure locale (GMT+1)
// ═══════════════════════════════════════════════════════════════════════
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
    // ─── last_seen: lire last_seen_at OU last_seen ─────────────────
    // Le backend (MessageController) envoie 'last_seen_at'
    // mais certains endroits utilisent 'last_seen'
    DateTime? lastSeen;
    final raw = json['last_seen_at'] ?? json['last_seen'];
    if (raw != null) {
      final parsed = DateTime.tryParse(raw.toString());
      lastSeen = parsed?.toLocal(); // convertir en heure locale
    }

    bool isOnline = json['is_online'] == true;
    if (!isOnline && lastSeen != null) {
      isOnline = DateTime.now().difference(lastSeen).inMinutes < 5;
    }

    return UserModel(
      id:       json['id']?.toString() ?? '',
      name:     json['name'] ?? json['full_name'] ?? '',
      email:    json['email'],
      photoUrl: json['profile_photo_url'] ?? json['photo_url'],
      isOnline: isOnline,
      lastSeen: lastSeen,
      role:     json['role'],
      phone:    json['phone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id':               id,
      'name':             name,
      'email':            email,
      'profile_photo_url': photoUrl,
      'is_online':        isOnline,
      'last_seen':        lastSeen?.toIso8601String(),
      'role':             role,
      'phone':            phone,
    };
  }
}