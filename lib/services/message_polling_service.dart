// Ce fichier est conservé pour compatibilité d'import.
// Le polling a été remplacé par WebSocket pur (PusherService).
// Aucune logique ici — tout passe par MessageProvider + PusherService.

@Deprecated('Utilisez PusherService + MessageProvider à la place')
class MessagePollingService {
  static final MessagePollingService _i = MessagePollingService._();
  factory MessagePollingService() => _i;
  MessagePollingService._();

  bool get isRunning => false;
  void start() {}
  void stop() {}
  void restart() {}
  void dispose() {}
  void setActiveConversation(String? _) {}
}
