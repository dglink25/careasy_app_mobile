class ReportReason {
  final String id;
  final String label;
  final bool requiresDetails;

  const ReportReason({
    required this.id,
    required this.label,
    this.requiresDetails = false,
  });

  static const List<ReportReason> reasons = [
    ReportReason(id: 'service_not_provided', label: 'Service non fourni'),
    ReportReason(id: 'poor_quality', label: 'Qualité médiocre'),
    ReportReason(id: 'unprofessional_behavior', label: 'Comportement non professionnel'),
    ReportReason(id: 'no_show', label: 'Rendez-vous non honoré'),
    ReportReason(id: 'price_mismatch', label: 'Prix non respecté'),
    ReportReason(id: 'inappropriate_content', label: 'Contenu inapproprié'),
    ReportReason(id: 'other', label: 'Autre (précisez)', requiresDetails: true),
  ];

  static ReportReason? fromId(String id) {
    return reasons.firstWhere((r) => r.id == id, orElse: () => reasons.last);
  }
}