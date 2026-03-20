// lib/models/rendez_vous_model.dart

class RendezVousModel {
  final String id;
  final String serviceId;
  final String clientId;
  final String prestataireId;
  final String entrepriseId;
  final String date;        // format: 'yyyy-MM-dd'
  final String startTime;   // format: 'HH:mm'
  final String endTime;
  final String status;      // pending | confirmed | cancelled | completed
  final String? clientNotes;
  final String? prestataireNotes;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  // Relations chargées avec la réponse
  final Map<String, dynamic>? service;
  final Map<String, dynamic>? client;
  final Map<String, dynamic>? prestataire;
  final Map<String, dynamic>? entreprise;

  const RendezVousModel({
    required this.id,
    required this.serviceId,
    required this.clientId,
    required this.prestataireId,
    required this.entrepriseId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.clientNotes,
    this.prestataireNotes,
    this.confirmedAt,
    this.cancelledAt,
    this.completedAt,
    required this.createdAt,
    this.service,
    this.client,
    this.prestataire,
    this.entreprise,
  });

  factory RendezVousModel.fromJson(Map<String, dynamic> json) {
    return RendezVousModel(
      id             : json['id']?.toString() ?? '',
      serviceId      : json['service_id']?.toString() ?? '',
      clientId       : json['client_id']?.toString() ?? '',
      prestataireId  : json['prestataire_id']?.toString() ?? '',
      entrepriseId   : json['entreprise_id']?.toString() ?? '',
      date           : json['date']?.toString().substring(0, 10) ?? '',
      startTime      : json['start_time']?.toString().substring(0, 5) ?? '',
      endTime        : json['end_time']?.toString().substring(0, 5) ?? '',
      status         : json['status']?.toString() ?? 'pending',
      clientNotes    : json['client_notes']?.toString(),
      prestataireNotes: json['prestataire_notes']?.toString(),
      confirmedAt    : _parseDate(json['confirmed_at']),
      cancelledAt    : _parseDate(json['cancelled_at']),
      completedAt    : _parseDate(json['completed_at']),
      createdAt      : _parseDate(json['created_at']) ?? DateTime.now(),
      service        : json['service']  is Map ? Map<String, dynamic>.from(json['service']  as Map) : null,
      client         : json['client']   is Map ? Map<String, dynamic>.from(json['client']   as Map) : null,
      prestataire    : json['prestataire'] is Map ? Map<String, dynamic>.from(json['prestataire'] as Map) : null,
      entreprise     : json['entreprise'] is Map ? Map<String, dynamic>.from(json['entreprise'] as Map) : null,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try { return DateTime.parse(v.toString()).toLocal(); } catch (_) { return null; }
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  bool get isPending   => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get canBeCancelled => status == 'pending' || status == 'confirmed';

  String get serviceName   => service?['name']?.toString()   ?? '—';
  String get entrepriseName => entreprise?['name']?.toString() ?? '—';
  String get clientName    => client?['name']?.toString()    ?? '—';
  String get prestataireName => prestataire?['name']?.toString() ?? '—';

  /// Retourne une description lisible du statut
  String get statusLabel {
    switch (status) {
      case 'pending':   return 'En attente';
      case 'confirmed': return 'Confirmé';
      case 'cancelled': return 'Annulé';
      case 'completed': return 'Terminé';
      default:          return status;
    }
  }

  /// Formate la date en "lundi 12 janvier 2025"
  String get formattedDate {
    try {
      final d = DateTime.parse(date);
      const months = ['janvier','février','mars','avril','mai','juin',
                      'juillet','août','septembre','octobre','novembre','décembre'];
      const days = ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'];
      final dayIdx = d.weekday - 1;
      return '${days[dayIdx]} ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return date;
    }
  }

  String get timeRange => '$startTime – $endTime';
}

// ── Modèle pour un créneau disponible ────────────────────────────────────────
class TimeSlot {
  final String start;
  final String end;
  final String display;

  const TimeSlot({
    required this.start,
    required this.end,
    required this.display,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    start   : json['start']   ?? '',
    end     : json['end']     ?? '',
    display : json['display'] ?? '${json['start']} - ${json['end']}',
  );
}