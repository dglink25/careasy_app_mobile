class ApiEndpoints {
  static const String baseUrl = 'http://10.31.94.115:8000/api';
  
  // Auth
  static const String login = '/login';
  static const String register = '/register';
  static const String logout = '/logout';
  static const String googleAuth = '/google';
  
  // User
  static const String userProfile = '/user/profile';
  static const String userSettings = '/user/settings';
  static const String updateProfile = '/user/update-all';
  static const String updatePhoto = '/user/profile-photo';
  
  // Entreprises
  static const String entreprises = '/entreprises';
  static const String myEntreprises = '/entreprises/mine';
  static const String entreprisesFormData = '/entreprises/form/data';
  static const String search = '/search';
  
  // Services
  static const String services = '/services';
  static const String myServices = '/services/mine';
  
  // Messages
  static const String conversations = '/conversations';
  static const String startConversation = '/conversation/start';
  static const String markAsRead = '/conversation';
  
  // Rendez-vous
  static const String rendezVous = '/rendez-vous';
  static const String calendar = '/rendez-vous/calendar';
  
  // Paiements
  static const String plans = '/plans';
  static const String abonnements = '/abonnements';
  static const String initierPaiement = '/paiements/initier';
  
  // IA
  static const String aiMessages = '/ai/messages';
  static const String nearbyServices = '/ai/services/nearby';
  static const String aiLocations = '/ai/locations';
  
  static String withBase(String endpoint) => baseUrl + endpoint;
}