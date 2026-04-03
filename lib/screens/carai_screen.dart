import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../utils/constants.dart';

// ─── Modèles ────────────────────────────────────────────────────────────────

class _CarAIMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final List<Map<String, dynamic>> services;
  final List<String> suggestions;
  final String? mapUrl;
  final String? intent;
  final bool isLoading;
  final DateTime createdAt;

  const _CarAIMessage({
    required this.id,
    required this.role,
    required this.content,
    this.services = const [],
    this.suggestions = const [],
    this.mapUrl,
    this.intent,
    this.isLoading = false,
    required this.createdAt,
  });

  _CarAIMessage copyWith({
    String? content,
    List<Map<String, dynamic>>? services,
    List<String>? suggestions,
    String? mapUrl,
    String? intent,
    bool? isLoading,
  }) =>
      _CarAIMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        services: services ?? this.services,
        suggestions: suggestions ?? this.suggestions,
        mapUrl: mapUrl ?? this.mapUrl,
        intent: intent ?? this.intent,
        isLoading: isLoading ?? this.isLoading,
        createdAt: createdAt,
      );
}

// ─── Widget principal ────────────────────────────────────────────────────────

class CarAIScreen extends StatefulWidget {
  const CarAIScreen({super.key});

  @override
  State<CarAIScreen> createState() => _CarAIScreenState();
}

class _CarAIScreenState extends State<CarAIScreen>
    with TickerProviderStateMixin {
  static const _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  final _messages = <_CarAIMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  bool _isLoading = false;
  String? _conversationId;
  double? _userLat;
  double? _userLng;

  // Animation du bouton envoi
  late AnimationController _sendAnim;

  @override
  void initState() {
    super.initState();
    _sendAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _startConversation();
    _tryGetLocation();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _sendAnim.dispose();
    super.dispose();
  }

  // ── Démarrer / retrouver la conversation ──────────────────────────────────
  Future<void> _startConversation() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/carai/conversations/start'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _conversationId = data['conversation_id']?.toString();

        // Charger l'historique si conversation existante
        if (data['is_new'] != true && _conversationId != null) {
          await _loadHistory();
        } else {
          // Message de bienvenue
          _addWelcome();
        }
      } else {
        _addWelcome();
      }
    } catch (e) {
      debugPrint('[CarAI] startConversation: $e');
      _addWelcome();
    }
  }

  void _addWelcome() {
    if (!mounted) return;
    setState(() {
      _messages.add(_CarAIMessage(
        id: 'welcome',
        role: 'assistant',
        content:
            '🚗 Bonjour ! Je suis **CarAI**, votre assistant automobile CarEasy.\n\n'
            'Je peux vous aider à trouver :\n'
            '• 🔧 Un garage / mécanicien\n'
            '• 🛞 Un vulcanisateur\n'
            '• 🚿 Un centre de lavage\n'
            '• ⚡ Un électricien auto\n'
            '• 🏁 Et bien d\'autres services !\n\n'
            'Dites-moi ce dont vous avez besoin.',
        suggestions: [
          '🔧 Trouver un garage',
          '🛞 Vulcanisateur proche',
          '🚿 Lavage auto',
          '⛽ Station essence',
        ],
        createdAt: DateTime.now(),
      ));
    });
  }

  // ── Historique ────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_conversationId == null) return;
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      final resp = await http.get(
        Uri.parse(
            '${AppConstants.apiBaseUrl}/carai/conversations/$_conversationId/messages?limit=20'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['data'] as List? ?? []);
        if (list.isEmpty) {
          _addWelcome();
          return;
        }
        if (!mounted) return;
        setState(() {
          for (final item in list) {
            final role =
                item['role']?.toString() == 'user' ? 'user' : 'assistant';
            final meta =
                item['ai_metadata'] as Map<String, dynamic>? ?? {};
            _messages.add(_CarAIMessage(
              id: item['id']?.toString() ?? UniqueKey().toString(),
              role: role,
              content: item['content']?.toString() ?? '',
              services: _parseServices(meta['services']),
              suggestions: _parseStrList(meta['suggestions']),
              mapUrl: meta['map_url']?.toString(),
              intent: meta['intent']?.toString(),
              createdAt: DateTime.tryParse(
                      item['created_at']?.toString() ?? '') ??
                  DateTime.now(),
            ));
          }
        });
        _scrollToBottom();
      } else {
        _addWelcome();
      }
    } catch (e) {
      debugPrint('[CarAI] loadHistory: $e');
      _addWelcome();
    }
  }

  // ── GPS ───────────────────────────────────────────────────────────────────
  Future<void> _tryGetLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      _userLat = pos.latitude;
      _userLng = pos.longitude;
    } catch (_) {}
  }

  // ── Envoi d'un message ────────────────────────────────────────────────────
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    _inputCtrl.clear();
    _inputFocus.unfocus();

    final userMsg = _CarAIMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: text.trim(),
      createdAt: DateTime.now(),
    );

    final loadingMsg = _CarAIMessage(
      id: 'loading',
      role: 'assistant',
      content: '',
      isLoading: true,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(loadingMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');

      // Obtenir la position si pas encore fait
      if (_userLat == null) await _tryGetLocation();

      final body = <String, dynamic>{
        'message': text.trim(),
        'conversation_id':
            int.tryParse(_conversationId ?? '0') ?? 0,
        if (_userLat != null) 'latitude': _userLat,
        if (_userLng != null) 'longitude': _userLng,
      };

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/carai/chat'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));

      if (!mounted) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      // Mettre à jour le conversationId si absent
      if (_conversationId == null && data['conversation_id'] != null) {
        _conversationId = data['conversation_id'].toString();
      }

      final aiMsg = _CarAIMessage(
        id: data['message_id']?.toString() ??
            'ai_${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: data['reply']?.toString() ?? 'Désolé, je n\'ai pas compris.',
        services: _parseServices(data['services']),
        suggestions: _parseStrList(data['suggestions']),
        mapUrl: data['map_url']?.toString(),
        intent: data['intent']?.toString(),
        createdAt: DateTime.now(),
      );

      setState(() {
        _messages.removeWhere((m) => m.id == 'loading');
        _messages.add(aiMsg);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[CarAI] sendMessage: $e');
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == 'loading');
        _messages.add(_CarAIMessage(
          id: 'err_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content:
              '😔 Je suis momentanément indisponible. Réessaie dans quelques secondes.',
          suggestions: ['🔄 Réessayer', '🔧 Trouver un garage', '🛞 Vulcanisateur'],
          createdAt: DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // ── Effacer l'historique ──────────────────────────────────────────────────
  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Effacer la conversation'),
        content:
            const Text('Voulez-vous effacer tout l\'historique de cette conversation ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Annuler', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    if (_conversationId != null) {
      try {
        final token = await _storage.read(key: 'auth_token');
        await http.delete(
          Uri.parse(
              '${AppConstants.apiBaseUrl}/carai/conversations/$_conversationId'),
          headers: {
            'Authorization': 'Bearer $token ?? ""',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    setState(() {
      _messages.clear();
      _conversationId = null;
    });
    await _startConversation();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Map<String, dynamic>> _parseServices(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  List<String> _parseStrList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildMessage(_messages[i], isDark),
                  ),
          ),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: AppConstants.primaryRed,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Avatar IA
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CarAI',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Assistant automobile',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Effacer la conversation',
          onPressed: _clearHistory,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.smart_toy_rounded,
                size: 56, color: AppConstants.primaryRed),
          ),
          const SizedBox(height: 20),
          const Text('CarAI',
              style:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Votre assistant automobile intelligent',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Message bubble ─────────────────────────────────────────────────────────
  Widget _buildMessage(_CarAIMessage msg, bool isDark) {
    if (msg.isLoading) return _buildTypingIndicator(isDark);
    return msg.role == 'user'
        ? _buildUserBubble(msg, isDark)
        : _buildAIBubble(msg, isDark);
  }

  Widget _buildUserBubble(_CarAIMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 60),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryRed.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            msg.content,
            style:
                const TextStyle(color: Colors.white, fontSize: 14.5),
          ),
        ),
      ),
    );
  }

  Widget _buildAIBubble(_CarAIMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: AppConstants.primaryRed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bulle texte
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildRichText(msg.content, isDark),
                ),

                // Carte des services
                if (msg.services.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildServicesCard(msg.services, isDark),
                ],

                // Lien carte
                if (msg.mapUrl != null && msg.mapUrl!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildMapButton(msg.mapUrl!),
                ],

                // Suggestions
                if (msg.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildSuggestions(msg.suggestions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 40),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: AppConstants.primaryRed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 18),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _TypingDots(),
          ),
        ],
      ),
    );
  }

  // ── Rich text (gère **bold** et • listes) ─────────────────────────────────
  Widget _buildRichText(String text, bool isDark) {
    final textColor =
        isDark ? Colors.white : const Color(0xFF1E293B);
    final spans = <TextSpan>[];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        spans.add(TextSpan(
          text: parts[i],
          style: TextStyle(
              fontWeight: FontWeight.bold, color: textColor, fontSize: 14.5),
        ));
      } else {
        spans.add(TextSpan(
          text: parts[i],
          style: TextStyle(color: textColor, fontSize: 14.5, height: 1.5),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  // ── Services card ──────────────────────────────────────────────────────────
  Widget _buildServicesCard(
      List<Map<String, dynamic>> services, bool isDark) {
    return Column(
      children: services
          .take(3)
          .map((svc) => _buildServiceTile(svc, isDark))
          .toList(),
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> svc, bool isDark) {
    final entreprise =
        svc['entreprise'] as Map<String, dynamic>? ?? {};
    final name = svc['name']?.toString() ?? 'Service';
    final entrepriseName =
        entreprise['name']?.toString() ?? svc['entreprise_name']?.toString() ?? '';
    final phone = entreprise['call_phone']?.toString() ?? '';
    final whatsapp =
        entreprise['whatsapp_phone']?.toString() ?? '';
    final distance = svc['distance_km'];
    final logo = entreprise['logo']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppConstants.primaryRed.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppConstants.primaryRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              image: logo != null && logo.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(logo), fit: BoxFit.cover)
                  : null,
            ),
            child: logo == null || logo.isEmpty
                ? const Icon(Icons.build_rounded,
                    color: AppConstants.primaryRed, size: 22)
                : null,
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entrepriseName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entrepriseName,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (distance != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 11, color: AppConstants.primaryRed),
                      const SizedBox(width: 2),
                      Text(
                        '${distance}km',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppConstants.primaryRed,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phone.isNotEmpty)
                _actionIcon(
                  Icons.call_rounded,
                  Colors.green,
                  () => _launchUrl('tel:$phone'),
                ),
              if (whatsapp.isNotEmpty) ...[
                const SizedBox(width: 6),
                _actionIcon(
                  Icons.chat_rounded,
                  const Color(0xFF25D366),
                  () => _launchUrl(
                      'https://wa.me/${whatsapp.replaceAll('+', '')}'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  // ── Bouton carte ──────────────────────────────────────────────────────────
  Widget _buildMapButton(String url) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.map_rounded, color: Colors.blue, size: 16),
            SizedBox(width: 6),
            Text(
              'Voir sur la carte',
              style: TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ── Suggestions ───────────────────────────────────────────────────────────
  Widget _buildSuggestions(List<String> suggestions) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: suggestions
          .map((s) => GestureDetector(
                onTap: () => _sendMessage(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color:
                        AppConstants.primaryRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppConstants.primaryRed.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(
                      color: AppConstants.primaryRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  // ── Barre de saisie ───────────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Champ de saisie
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _inputCtrl,
                focusNode: _inputFocus,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (v) => _sendMessage(v),
                style: TextStyle(
                  color:
                      isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 14.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Posez votre question...',
                  hintStyle:
                      TextStyle(color: Colors.grey[400], fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Bouton envoi
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputCtrl,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: () => _sendMessage(_inputCtrl.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: hasText && !_isLoading
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFE63946),
                              Color(0xFFFF6B6B)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: hasText && !_isLoading
                        ? null
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: hasText && !_isLoading
                        ? [
                            BoxShadow(
                              color: AppConstants.primaryRed
                                  .withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 22),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[CarAI] launchUrl: $e');
    }
  }
}

// ─── Widget animation des points de frappe ────────────────────────────────────

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anims = List.generate(3, (i) {
      final start = i * 0.2;
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, start + 0.4, curve: Curves.easeInOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Transform.translate(
              offset: Offset(0, _anims[i].value),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppConstants.primaryRed,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Bouton flottant CarAI (à placer dans chaque écran) ───────────────────────

class CarAIFab extends StatelessWidget {
  const CarAIFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'carai_fab_${UniqueKey()}',
      backgroundColor: AppConstants.primaryRed,
      elevation: 6,
      tooltip: 'CarAI — Assistant automobile',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CarAIScreen()),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 26),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}