import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../utils/constants.dart';

// ─── Modèles ─────────────────────────────────────────────────────────────────

class _CarAIMessage {
  final String id;
  final String role;
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

// ─── Couleurs & Constantes UI ─────────────────────────────────────────────────

class _UI {
  static const Color primary    = Color(0xFFE63946);
  static const Color primaryDim = Color(0xFFFF6B6B);
  static const Color online     = Color(0xFF22C55E);
  static const Color surface    = Color(0xFFF8FAFC);
  static const Color surfaceDark= Color(0xFF0F172A);
  static const Color bubbleDark = Color(0xFF1E293B);
  static const Color text       = Color(0xFF1E293B);
  static const Color textMuted  = Color(0xFF94A3B8);
  static const Color mapBlue    = Color(0xFF3B82F6);
  static const Color whatsapp   = Color(0xFF25D366);
  static const Color callGreen  = Color(0xFF16A34A);
}

// ─── Écran principal CarAI ────────────────────────────────────────────────────

class CarAIScreen extends StatefulWidget {
  const CarAIScreen({super.key});

  @override
  State<CarAIScreen> createState() => _CarAIScreenState();
}

class _CarAIScreenState extends State<CarAIScreen>
    with TickerProviderStateMixin {
  static const _androidOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iosOpts =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage    = const FlutterSecureStorage(
    aOptions: _androidOpts, iOptions: _iosOpts,
  );
  final _messages   = <_CarAIMessage>[];
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  bool    _isLoading      = false;
  String? _conversationId;
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _startConversation();
    _tryGetLocation();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _startConversation() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) { _addWelcome(); return; }

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
        if (data['is_new'] != true && _conversationId != null) {
          await _loadHistory();
        } else {
          _addWelcome();
        }
      } else {
        _addWelcome();
      }
    } catch (_) {
      _addWelcome();
    }
  }

  void _addWelcome() {
    if (!mounted) return;
    setState(() {
      _messages.add(_CarAIMessage(
        id:      'welcome',
        role:    'assistant',
        content: 'Bonjour, je suis CarAI — votre assistant automobile CarEasy au Bénin.\n\n'
            'Je peux vous aider à trouver un mécanicien, un vulcanisateur, '
            'un centre de lavage, un électricien auto et bien d\'autres services. '
            'Dites-moi simplement ce dont vous avez besoin.',
        suggestions: [
          'Trouver un garage mécanique',
          'Vulcanisateur disponible',
          'Lavage auto',
          'Electricien auto',
        ],
        createdAt: DateTime.now(),
      ));
    });
  }

  Future<void> _loadHistory() async {
    if (_conversationId == null) return;
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) { _addWelcome(); return; }

      final resp = await http.get(
        Uri.parse(
          '${AppConstants.apiBaseUrl}/carai/conversations/$_conversationId/messages?limit=20',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['data'] as List? ?? []);
        if (list.isEmpty) { _addWelcome(); return; }
        if (!mounted) return;
        setState(() {
          for (final item in list) {
            final meta = item['ai_metadata'] as Map<String, dynamic>? ?? {};
            _messages.add(_CarAIMessage(
              id:          item['id']?.toString() ?? UniqueKey().toString(),
              role:        item['role']?.toString() == 'user' ? 'user' : 'assistant',
              content:     item['content']?.toString() ?? '',
              services:    _parseServices(meta['services']),
              suggestions: _parseStrList(meta['suggestions']),
              mapUrl:      meta['map_url']?.toString(),
              intent:      meta['intent']?.toString(),
              createdAt:   DateTime.tryParse(item['created_at']?.toString() ?? '')
                              ?? DateTime.now(),
            ));
          }
        });
        _scrollToBottom();
      } else {
        _addWelcome();
      }
    } catch (_) {
      _addWelcome();
    }
  }

  // ── Localisation GPS ──────────────────────────────────────────────────────

  Future<void> _tryGetLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        // Demande de permission silencieuse
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied ||
            req == LocationPermission.deniedForever) return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      _userLat = pos.latitude;
      _userLng = pos.longitude;
    } catch (_) {}
  }

  // ── Envoi de message ──────────────────────────────────────────────────────

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    _inputCtrl.clear();
    _inputFocus.unfocus();

    final loadingId = 'loading_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _messages.add(_CarAIMessage(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        role: 'user', content: trimmed, createdAt: DateTime.now(),
      ));
      _messages.add(_CarAIMessage(
        id: loadingId, role: 'assistant', content: '',
        isLoading: true, createdAt: DateTime.now(),
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Non authentifié');
      if (_userLat == null) await _tryGetLocation();

      final body = <String, dynamic>{
        'message':         trimmed,
        'conversation_id': int.tryParse(_conversationId ?? '0') ?? 0,
        if (_userLat != null) 'latitude':  _userLat,
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
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (_conversationId == null && data['conversation_id'] != null) {
        _conversationId = data['conversation_id'].toString();
      }

      setState(() {
        _messages.removeWhere((m) => m.id == loadingId);
        _messages.add(_CarAIMessage(
          id:          data['message_id']?.toString() ?? 'ai_${DateTime.now().millisecondsSinceEpoch}',
          role:        'assistant',
          content:     data['reply']?.toString() ?? 'Je n\'ai pas compris votre demande.',
          services:    _parseServices(data['services']),
          suggestions: _parseStrList(data['suggestions']),
          mapUrl:      data['map_url']?.toString(),
          intent:      data['intent']?.toString(),
          createdAt:   DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == loadingId);
        _messages.add(_CarAIMessage(
          id:          'err_${DateTime.now().millisecondsSinceEpoch}',
          role:        'assistant',
          content:     'Le service est momentanément indisponible. Veuillez réessayer dans quelques instants.',
          suggestions: ['Réessayer', 'Trouver un garage mécanique'],
          createdAt:   DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // ── Effacer l'historique ───────────────────────────────────────────────────

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.delete_sweep_rounded, color: _UI.primary, size: 22),
          const SizedBox(width: 10),
          const Text('Effacer la conversation',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        content: const Text(
          'Voulez-vous supprimer tout l\'historique de cette conversation ?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _UI.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    if (_conversationId != null) {
      try {
        final token = await _storage.read(key: 'auth_token');
        await http.delete(
          Uri.parse('${AppConstants.apiBaseUrl}/carai/conversations/$_conversationId'),
          headers: {
            'Authorization': 'Bearer ${token ?? ""}',
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
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Map<String, dynamic>> _parseServices(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  List<String> _parseStrList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  Future<void> _launchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? _UI.surfaceDark : _UI.surface,
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        _buildMessage(_messages[i], isDark),
                  ),
          ),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: _UI.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
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
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CarAI',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _UI.online,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Assistant automobile',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep_rounded, size: 22),
          tooltip: 'Effacer la conversation',
          onPressed: _clearHistory,
        ),
      ],
    );
  }

  // ── État vide ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: _UI.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_car_rounded,
              size: 44,
              color: _UI.primary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'CarAI',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : _UI.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Votre assistant automobile CarEasy',
            style: TextStyle(
                color: _UI.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  // ── Message dispatcher ────────────────────────────────────────────────────

  Widget _buildMessage(_CarAIMessage msg, bool isDark) {
    if (msg.isLoading) return _buildTypingIndicator(isDark);
    return msg.role == 'user'
        ? _buildUserBubble(msg, isDark)
        : _buildAIBubble(msg, isDark);
  }

  // ── Bulle utilisateur ─────────────────────────────────────────────────────

  Widget _buildUserBubble(_CarAIMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 60),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_UI.primary, _UI.primaryDim],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(18),
              topRight:    Radius.circular(18),
              bottomLeft:  Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: _UI.primary.withOpacity(0.22),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            msg.content,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.45),
          ),
        ),
      ),
    );
  }

  // ── Bulle assistant ───────────────────────────────────────────────────────

  Widget _buildAIBubble(_CarAIMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 9, top: 2),
            decoration: BoxDecoration(
              color: _UI.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bulle texte
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: isDark ? _UI.bubbleDark : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft:     Radius.circular(4),
                      topRight:    Radius.circular(18),
                      bottomLeft:  Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.055),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildRichText(msg.content, isDark),
                ),

                // Cartes prestataires
                if (msg.services.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  ...msg.services
                      .take(3)
                      .map((s) => _buildServiceCard(s, isDark)),
                ],

                // Bouton carte
                if (msg.mapUrl != null && msg.mapUrl!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildMapButton(msg.mapUrl!, isDark),
                ],

                // Suggestions
                if (msg.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _buildSuggestions(msg.suggestions, isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Indicateur de frappe ──────────────────────────────────────────────────

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 9, top: 2),
            decoration: BoxDecoration(
              color: _UI.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: isDark ? _UI.bubbleDark : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(4),
                topRight:    Radius.circular(18),
                bottomLeft:  Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.055),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  // ── Texte riche (gestion **bold**) ────────────────────────────────────────

  Widget _buildRichText(String text, bool isDark) {
    final textColor = isDark ? Colors.white : _UI.text;
    final parts     = text.split('**');
    final spans     = <TextSpan>[];
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.w400,
          color: textColor,
          fontSize: 14,
          height: 1.55,
        ),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }

  // ── Carte prestataire ─────────────────────────────────────────────────────

  Widget _buildServiceCard(Map<String, dynamic> svc, bool isDark) {
    final e    = svc['entreprise'] as Map<String, dynamic>? ?? {};
    final name = svc['name']?.toString() ?? 'Service';
    final ent  = e['name']?.toString() ?? '';
    final ph   = e['call_phone']?.toString() ?? '';
    final wa   = e['whatsapp_phone']?.toString() ?? '';
    final dist = svc['distance_km'];
    final logo = e['logo']?.toString();
    final note = (svc['average_rating'] as num?)?.toDouble();
    final avis = (svc['total_reviews'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isDark ? _UI.bubbleDark : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _UI.primary.withOpacity(0.12),
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
          // Logo / icône
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _UI.primary.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10),
              image: logo != null && logo.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(logo),
                      fit: BoxFit.cover)
                  : null,
            ),
            child: (logo == null || logo.isEmpty)
                ? const Icon(
                    Icons.store_rounded,
                    color: _UI.primary,
                    size: 20,
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Informations
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isDark ? Colors.white : _UI.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ent.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ent,
                    style: const TextStyle(
                        fontSize: 12, color: _UI.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (dist != null) ...[
                      const Icon(
                        Icons.near_me_rounded,
                        size: 11,
                        color: _UI.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${dist} km',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _UI.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (note != null && avis > 0) ...[
                      const Icon(
                        Icons.star_rounded,
                        size: 11,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$note ($avis)',
                        style: const TextStyle(
                            fontSize: 11, color: _UI.textMuted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Boutons d'action
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ph.isNotEmpty)
                _iconBtn(
                  icon: Icons.call_rounded,
                  color: _UI.callGreen,
                  onTap: () => _launchUrl('tel:$ph'),
                  tooltip: 'Appeler',
                ),
              if (wa.isNotEmpty) ...[
                const SizedBox(width: 6),
                _iconBtn(
                  icon: Icons.chat_rounded,
                  color: _UI.whatsapp,
                  onTap: () => _launchUrl(
                    'https://wa.me/${wa.replaceAll('+', '').replaceAll(' ', '')}',
                  ),
                  tooltip: 'WhatsApp',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }

  // ── Bouton carte ──────────────────────────────────────────────────────────

  Widget _buildMapButton(String url, bool isDark) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _UI.mapBlue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _UI.mapBlue.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.map_rounded, color: _UI.mapBlue, size: 15),
            SizedBox(width: 6),
            Text(
              'Voir sur la carte',
              style: TextStyle(
                color: _UI.mapBlue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded, color: _UI.mapBlue, size: 12),
          ],
        ),
      ),
    );
  }

  // ── Suggestions ───────────────────────────────────────────────────────────

  Widget _buildSuggestions(List<String> suggestions, bool isDark) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: suggestions.map((s) {
        return GestureDetector(
          onTap: () => _sendMessage(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? _UI.primary.withOpacity(0.12)
                  : _UI.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _UI.primary.withOpacity(0.28),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 12,
                  color: _UI.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  s,
                  style: const TextStyle(
                    color: _UI.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Barre de saisie ───────────────────────────────────────────────────────

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14, 10, 14, 10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? _UI.bubbleDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Champ texte
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller:      _inputCtrl,
                focusNode:       _inputFocus,
                maxLines:        5,
                minLines:        1,
                textInputAction: TextInputAction.send,
                onSubmitted:     _sendMessage,
                style: TextStyle(
                  color:    isDark ? Colors.white : _UI.text,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Posez votre question...',
                  hintStyle: const TextStyle(
                      color: _UI.textMuted, fontSize: 14),
                  border:         InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),

          // Bouton envoi
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputCtrl,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              final active  = hasText && !_isLoading;
              return GestureDetector(
                onTap: active ? () => _sendMessage(_inputCtrl.text) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width:  46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: active
                        ? const LinearGradient(
                            colors: [_UI.primary, _UI.primaryDim],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: active ? null : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: _UI.primary.withOpacity(0.3),
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
                      : Icon(
                          Icons.send_rounded,
                          color: active ? Colors.white : Colors.grey.shade500,
                          size: 20,
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Animation des 3 points de frappe ────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

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
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _anims = List.generate(3, (i) {
      final start = i * 0.18;
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, start + 0.38, curve: Curves.easeInOut),
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
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width:  8,
              height: 8,
              decoration: BoxDecoration(
                color: _UI.primary.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Bouton flottant CarAI (FloatingActionButton) ─────────────────────────────

class CarAIFab extends StatelessWidget {
  const CarAIFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag:         'carai_fab_unique',
      backgroundColor: _UI.primary,
      elevation:       6,
      tooltip:         'Assistant automobile CarAI',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CarAIScreen()),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.support_agent_rounded,
            color: Colors.white,
            size: 26,
          ),
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width:  10,
              height: 10,
              decoration: BoxDecoration(
                color:  _UI.online,
                shape:  BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}