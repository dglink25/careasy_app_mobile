import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../providers/message_provider.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';
import '../services/pusher_service.dart';
import '../services/message_service.dart';
import '../services/audio_metadata_cache.dart';
import 'media_viewer_screen.dart';

class ChatScreen extends StatefulWidget {
  final String    conversationId;
  final UserModel otherUser;
  final String?   serviceName;
  final String?   entrepriseName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
    this.serviceName,
    this.entrepriseName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── Contrôleurs UI ────────────────────────────────────────────────────────
  final TextEditingController _msgCtrl    = TextEditingController();
  final ScrollController      _scroll     = ScrollController();
  final FocusNode             _focus      = FocusNode();
  final ImagePicker           _picker     = ImagePicker();
  final AudioRecorder         _rec        = AudioRecorder();
  final Map<String, AudioPlayer>            _players = {};
  final Map<String, VideoPlayerController>  _vCtrl       = {};
  final Map<String, ChewieController>       _cCtrl       = {};
  final Set<String>                         _vInitializing = {};
  final Set<String>                         _vError        = {};

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions     = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(
      aOptions: _androidOptions, iOptions: _iOSOptions);

  // ── État envoi ────────────────────────────────────────────────────────────
  bool _sending    = false;
  bool _hasText    = false;
  bool _sendingLoc = false;

  // ── Scroll intelligent ────────────────────────────────────────────────────
  bool _isAtBottom = true; // scroll auto uniquement si on est en bas

  // ── Typing indicator (WhatsApp-like) ─────────────────────────────────────
  bool   _typingActive   = false;
  Timer? _typingTimer;
  Timer? _typingDebounce; // debounce 300ms avant typing=false

  // ── Recherche ─────────────────────────────────────────────────────────────
  bool                    _isSearching       = false;
  final TextEditingController _searchCtrl    = TextEditingController();
  String                  _searchQuery       = '';
  List<int>               _searchResults     = [];
  int                     _searchCurrentIndex = -1;

  // ── Réponse / Modification ────────────────────────────────────────────────
  MessageModel? _replyTo;
  MessageModel? _editingMessage;
  bool          _isEditing = false;

  // ── Emoji picker ──────────────────────────────────────────────────────────
  bool _showEmojiPicker = false;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _micScaleCtrl;
  late Animation<double>   _micScaleAnim;
  late AnimationController _waveCtrl;

  // ── Enregistrement vocal ──────────────────────────────────────────────────
  bool     _recActive   = false;
  bool     _recLocked   = false;
  bool     _recPreview  = false;
  String?  _recPath;
  Duration _recDuration = Duration.zero;
  Timer?   _recTimer;

  final List<double> _waveformBars = List.filled(40, 0.1);
  Timer?             _waveformTimer;
  final math.Random  _rand          = math.Random();
  double             _currentAmplitude = 0.0;

  final GlobalKey _micKey         = GlobalKey();
  Offset?         _micTouchStart;
  double          _micDragY       = 0.0;
  double          _micDragX       = 0.0;
  bool            _showSwipeHint  = false;

  static const double _kCancelX = -80.0;
  static const double _kLockY   = -80.0;

  // ── Preview audio ─────────────────────────────────────────────────────────
  AudioPlayer?        _previewPlayer;
  bool                _previewPlaying = false;
  Duration            _previewPos     = Duration.zero;
  Duration            _previewDur     = Duration.zero;
  StreamSubscription? _previewPosSub;
  StreamSubscription? _previewStateSub;

  // ── Provider ──────────────────────────────────────────────────────────────
  MessageProvider? _msgProvider;

  // ── Cache durées audio ────────────────────────────────────────────────────
  final AudioMetadataCache _audioMeta = AudioMetadataCache();

  // ── Emojis fréquents ──────────────────────────────────────────────────────
  final List<String> _frequentEmojis = [
    '😀','😂','🥰','😍','🤩','😎','🤔','😅','😭','😤',
    '🎉','👍','👎','❤️','🔥','✅','⚡','🙏','💪','😴',
    '🌟','💯','🤝','👏','🥳','😮','🤣','😊','😢','😡',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnimations();

    _msgCtrl.addListener(_onTextChanged);
    _searchCtrl.addListener(_onSearchChanged);
    _scroll.addListener(_onScrollChanged); // scroll intelligent

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _msgProvider = context.read<MessageProvider>();
      _msgProvider!.setActiveConversation(widget.conversationId);
      _loadMessages();
      _msgProvider!.fetchOnlineStatus(widget.otherUser.id);
      NotificationService().cancelNotification(widget.conversationId);
      NotificationService().onNotificationTap = (data) {
        final convId = data['conversation_id']?.toString() ?? '';
        if (convId != widget.conversationId && mounted) Navigator.pop(context);
      };

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showSwipeHint = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showSwipeHint = false);
        });
      });
    });
  }

  void _initAnimations() {
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _micScaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _micScaleAnim = Tween<double>(begin: 1.0, end: 1.3)
        .animate(CurvedAnimation(parent: _micScaleCtrl, curve: Curves.elasticOut));

    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100))
      ..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _msgProvider ??= context.read<MessageProvider>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _msgProvider?.loadMessages(widget.conversationId);
      _msgProvider?.fetchOnlineStatus(widget.otherUser.id);
      _markRead();
      NotificationService().cancelNotification(widget.conversationId);
      _msgProvider?.setActiveConversation(widget.conversationId);
    } else if (state == AppLifecycleState.paused) {
      _msgProvider?.setActiveConversation(null);
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _recTimer?.cancel();
    _waveformTimer?.cancel();
    _pulseCtrl.dispose();
    _micScaleCtrl.dispose();
    _waveCtrl.dispose();
    _searchCtrl.dispose();
    _scroll.removeListener(_onScrollChanged);

    // Indiquer que la conversation n'est plus active
    _msgProvider?.setActiveConversation(null);

    // Désabonner le canal WebSocket de cette conversation
    PusherService().unsubscribeFromConversation(widget.conversationId);

    // Arrêter proprement les indicateurs
    if (_typingActive) {
      _msgProvider?.sendTypingIndicator(widget.conversationId, false);
    }
    if (_recActive) {
      _rec.stop().catchError((_) => null).then((p) {
        if (p != null) try { File(p).deleteSync(); } catch (_) {}
      });
      _msgProvider?.sendRecordingIndicator(widget.conversationId, false);
    }

    _rec.dispose();
    _disposePreview();
    for (final p in _players.values) p.dispose();
    for (final c in _vCtrl.values)   c.dispose();
    for (final c in _cCtrl.values)   c.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    _focus.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SCROLL INTELLIGENT
  // ═══════════════════════════════════════════════════════════════════════════

  void _onScrollChanged() {
    if (!_scroll.hasClients) return;
    final isAtBottom =
        _scroll.position.maxScrollExtent - _scroll.offset < 120;
    if (isAtBottom != _isAtBottom) {
      setState(() => _isAtBottom = isAtBottom);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CHARGEMENT & LECTURE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadMessages() async {
    await _msgProvider?.loadMessages(widget.conversationId);
    _markRead();
    _scrollBottom(animated: false);
    // Pré-charger les durées de tous les audios de la conversation
    _preloadAudioDurations();
  }

  /// Pré-charge la durée de chaque message vocal/audio visible.
  void _preloadAudioDurations() {
    final msgs = _msgProvider?.getMessages(widget.conversationId) ?? [];
    final batch = <({String msgId, String src})>[];
    for (final m in msgs) {
      if (m.type != 'audio' && m.type != 'vocal') continue;
      final src = m.effectiveMediaUrl;
      if (src == null || src.isEmpty) continue;
      batch.add((msgId: m.id, src: src));
    }
    if (batch.isEmpty) return;
    _audioMeta.preloadBatch(batch, notify: () {
      if (mounted) setState(() {});
    });
  }

  /// Appelé à chaque rebuild du Consumer — ne charge que les audios
  /// pas encore en cache (idempotent, très peu coûteux).
  void _preloadNewAudioDurations(List<MessageModel> msgs) {
    for (final m in msgs) {
      if (m.type != 'audio' && m.type != 'vocal') continue;
      final src = m.effectiveMediaUrl;
      if (src == null || src.isEmpty) continue;
      if (_audioMeta.getDuration(m.id) != null) continue; // déjà en cache
      _audioMeta.preload(m.id, src, notify: () {
        if (mounted) setState(() {});
      });
    }
  }

  void _markRead() =>
      _msgProvider?.markConversationAsRead(widget.conversationId);

  void _scrollBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animated && max > 0) {
        _scroll.animateTo(max,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  TYPING INDICATOR (WhatsApp-like avec debounce)
  // ═══════════════════════════════════════════════════════════════════════════

  void _onTextChanged() {
    final hasText = _msgCtrl.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);

    _typingDebounce?.cancel();

    if (hasText) {
      // Envoyer typing=true immédiatement au premier caractère
      if (!_typingActive) {
        _typingActive = true;
        _msgProvider?.sendTypingIndicator(widget.conversationId, true);
      }
      // Auto-stop après 3s d'inactivité clavier
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (_typingActive) {
          _typingActive = false;
          _msgProvider?.sendTypingIndicator(widget.conversationId, false);
        }
      });
    } else {
      // Debounce 300ms avant d'envoyer typing=false
      _typingDebounce = Timer(const Duration(milliseconds: 300), () {
        if (_typingActive) {
          _typingActive = false;
          _msgProvider?.sendTypingIndicator(widget.conversationId, false);
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  RECHERCHE
  // ═══════════════════════════════════════════════════════════════════════════

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _searchQuery        = q;
      _searchResults      = [];
      _searchCurrentIndex = -1;
    });
    if (q.isEmpty) return;

    final msgs    = _msgProvider?.getMessages(widget.conversationId) ?? [];
    final results = <int>[];
    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].content.toLowerCase().contains(q)) results.add(i);
    }
    setState(() {
      _searchResults      = results.reversed.toList();
      if (_searchResults.isNotEmpty) {
        _searchCurrentIndex = 0;
        _scrollToMessage(_searchResults[0]);
      }
    });
  }

  void _scrollToMessage(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final msgs  = _msgProvider?.getMessages(widget.conversationId) ?? [];
      if (index >= msgs.length) return;
      final ratio = index / msgs.length;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent * ratio,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _navigateSearchResult(bool next) {
    if (_searchResults.isEmpty) return;
    setState(() {
      _searchCurrentIndex = next
          ? (_searchCurrentIndex + 1) % _searchResults.length
          : (_searchCurrentIndex - 1 + _searchResults.length) % _searchResults.length;
    });
    _scrollToMessage(_searchResults[_searchCurrentIndex]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ENVOI / MODIFICATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _send({
    String? content,
    String? filePath,
    String? type,
    double? lat,
    double? lng,
  }) async {
    if (_isEditing && _editingMessage != null) {
      await _saveEdit(content ?? _msgCtrl.text.trim());
      return;
    }

    final text = content?.trim() ?? '';
    if (text.isEmpty && filePath == null && lat == null) return;
    if (_sending) return;

    // Couper immédiatement l'indicateur typing avant envoi
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    if (_typingActive) {
      _typingActive = false;
      _msgProvider?.sendTypingIndicator(widget.conversationId, false);
    }

    setState(() => _sending = true);
    try {
      final t = type ?? (filePath != null ? _fileType(filePath) : 'text');
      await _msgProvider?.sendMessage(
        widget.conversationId,
        type     : lat != null ? 'location' : t,
        content  : text.isEmpty ? null : text,
        filePath : filePath,
        latitude : lat,
        longitude: lng,
        replyToId: _replyTo?.id,
      );
      if (type == null || type == 'text') {
        _msgCtrl.clear();
        setState(() { _hasText = false; _replyTo = null; });
      }
      _scrollBottom();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _showErr(msg.isNotEmpty ? msg : "Impossible d'envoyer");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _canEdit(MessageModel msg) {
    if (!msg.isMe)         return false;
    if (msg.type != 'text') return false;
    return DateTime.now().difference(msg.createdAt).inMinutes < 15;
  }

  void _startEdit(MessageModel msg) {
    setState(() {
      _editingMessage = msg;
      _isEditing      = true;
      _replyTo        = null;
    });
    _msgCtrl.text = msg.content;
    _msgCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _msgCtrl.text.length));
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() { _editingMessage = null; _isEditing = false; });
    _msgCtrl.clear();
    setState(() => _hasText = false);
  }

  Future<void> _saveEdit(String newContent) async {
    if (_editingMessage == null || newContent.trim().isEmpty) return;
    setState(() => _sending = true);

    final msgId  = _editingMessage!.id;
    final convId = widget.conversationId;
    final trimmed = newContent.trim();

    // Patch optimiste local immédiat — l'UI répond instantanément
    _msgProvider?.patchMessageContent(convId, msgId, trimmed);

    try {
      final token = await _storage.read(key: 'auth_token');
      final resp  = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/messages/$msgId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
          'Accept'       : 'application/json',
        },
        body: jsonEncode({'content': trimmed}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        // Annuler le patch local si le serveur refuse
        _msgProvider?.patchMessageContent(convId, msgId, _editingMessage!.content);
        _showErr('Erreur modification');
      }
    } catch (_) {
      _msgProvider?.patchMessageContent(convId, msgId, _editingMessage!.content);
      _showErr('Erreur de connexion');
    } finally {
      if (mounted) {
        setState(() {
          _editingMessage = null;
          _isEditing      = false;
          _sending        = false;
          _hasText        = false;
        });
        _msgCtrl.clear();
      }
    }
  }

  Future<void> _deleteMessage(MessageModel msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title  : const Text('Supprimer le message'),
        content: const Text('Voulez-vous supprimer ce message ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;

    final convId = widget.conversationId;
    final msgId  = msg.id;

    // Suppression optimiste locale — l'UI répond instantanément
    _msgProvider?.removeMessage(convId, msgId);

    try {
      final token = await _storage.read(key: 'auth_token');
      final resp = await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/messages/$msgId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept'       : 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200 && resp.statusCode != 204) {
        // Réinsérer le message si le serveur refuse
        _msgProvider?.loadMessages(convId);
        _showErr('Erreur suppression');
      }
    } catch (_) {
      _msgProvider?.loadMessages(convId);
      _showErr('Erreur de connexion');
    }
  }

  // ── Helpers fichiers ──────────────────────────────────────────────────────

  String _fileType(String p) {
    final e = p.split('.').last.toLowerCase();
    if (['jpg','jpeg','png','gif','webp'].contains(e)) return 'image';
    if (['mp4','mov','avi','mkv','3gp'].contains(e))   return 'video';
    if (['mp3','m4a','aac','wav','ogg'].contains(e))   return 'audio';
    return 'document';
  }

  Future<void> _pickImg(ImageSource s) async {
    try {
      final f = await _picker.pickImage(
          source: s, maxWidth: 1024, imageQuality: 80);
      if (f != null) await _send(filePath: f.path, type: 'image');
    } catch (_) { _showErr('Erreur photo'); }
  }

  Future<void> _pickVid(ImageSource s) async {
    try {
      final f = await _picker.pickVideo(source: s);
      if (f == null) return;
      // Vérifier la taille : max 100 Mo
      final size = await File(f.path).length();
      if (size > 100 * 1024 * 1024) {
        _showErr('Vidéo trop lourde (max 100 Mo)');
        return;
      }
      await _send(filePath: f.path, type: 'video');
    } catch (_) { _showErr('Erreur vidéo'); }
  }

  Future<void> _pickDoc() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowCompression: false,
      );
      if (r?.files.single.path == null) return;
      final path = r!.files.single.path!;
      // Vérifier la taille : max 100 Mo
      final size = await File(path).length();
      if (size > 100 * 1024 * 1024) {
        _showErr('Fichier trop lourd (max 100 Mo)');
        return;
      }
      await _send(filePath: path, type: 'document');
    } catch (_) { _showErr('Erreur document'); }
  }

  Future<void> _sendLoc() async {
    if (_sendingLoc) return;
    setState(() => _sendingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showErr('Permission refusée');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      String addr =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final m = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (m.isNotEmpty) {
          final p   = m.first;
          final pts = [
            if (p.street?.isNotEmpty == true)   p.street!,
            if (p.locality?.isNotEmpty == true)  p.locality!,
            if (p.country?.isNotEmpty == true)   p.country!,
          ];
          if (pts.isNotEmpty) addr = pts.join(', ');
        }
      } catch (_) {}
      await _send(
          content: addr, type: 'location',
          lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      _showErr('Erreur localisation');
    } finally {
      if (mounted) setState(() => _sendingLoc = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ENREGISTREMENT VOCAL
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startRec() async {
    if (_recActive || _recPreview) return;
    if (!await _rec.hasPermission()) {
      _showErr('Permission microphone refusée');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final p   = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100),
        path: p,
      );
      _micScaleCtrl.forward();
      setState(() {
        _recActive   = true;
        _recLocked   = false;
        _recDuration = Duration.zero;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recActive && mounted) {
          setState(() => _recDuration =
              Duration(seconds: _recDuration.inSeconds + 1));
        }
      });
      _startWaveformSimulation();
      _msgProvider?.sendRecordingIndicator(widget.conversationId, true);
    } catch (_) {
      _showErr("Impossible de démarrer l'enregistrement");
    }
  }

  void _startWaveformSimulation() {
    _waveformTimer?.cancel();
    _waveformTimer =
        Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_recActive || !mounted) return;
      setState(() {
        for (int i = 0; i < _waveformBars.length - 1; i++) {
          _waveformBars[i] = _waveformBars[i + 1];
        }
        _currentAmplitude = 0.1 + _rand.nextDouble() * 0.85;
        final prev = _waveformBars[_waveformBars.length - 2];
        _waveformBars[_waveformBars.length - 1] =
            (prev * 0.3 + _currentAmplitude * 0.7).clamp(0.05, 1.0);
      });
    });
  }

  void _stopWaveformSimulation() {
    _waveformTimer?.cancel();
    Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) { t.cancel(); return; }
      bool allZero = true;
      setState(() {
        for (int i = 0; i < _waveformBars.length; i++) {
          _waveformBars[i] = (_waveformBars[i] * 0.7).clamp(0.05, 1.0);
          if (_waveformBars[i] > 0.06) allZero = false;
        }
      });
      if (allZero) t.cancel();
    });
  }

  Future<void> _stopForPreview() async {
    if (!_recActive) return;
    _recTimer?.cancel();
    _micScaleCtrl.reverse();
    _stopWaveformSimulation();
    _msgProvider?.sendRecordingIndicator(widget.conversationId, false);
    final dur = _recDuration;
    try {
      final p = await _rec.stop();
      if (!mounted) return;
      if (p != null && dur.inSeconds >= 1) {
        await _initPreview(p);
        setState(() {
          _recActive  = false;
          _recLocked  = false;
          _recPreview = true;
          _recPath    = p;
          _micDragX   = 0;
          _micDragY   = 0;
        });
      } else {
        if (p != null) try { File(p).deleteSync(); } catch (_) {}
        setState(() {
          _recActive   = false;
          _recLocked   = false;
          _recDuration = Duration.zero;
        });
        if (dur.inSeconds < 1) _showErr('Trop court (min. 1 s)');
      }
    } catch (_) {
      if (mounted) setState(() { _recActive = false; _recLocked = false; });
    }
  }

  Future<void> _cancelRec() async {
    _recTimer?.cancel();
    _micScaleCtrl.reverse();
    _stopWaveformSimulation();
    _msgProvider?.sendRecordingIndicator(widget.conversationId, false);
    try {
      final p = await _rec.stop();
      if (p != null) try { File(p).deleteSync(); } catch (_) {}
    } catch (_) {}
    if (mounted) {
      setState(() {
        _recActive   = false;
        _recLocked   = false;
        _recDuration = Duration.zero;
        _micDragX    = 0;
        _micDragY    = 0;
      });
    }
    HapticFeedback.lightImpact();
  }

  void _cancelPreview() {
    _disposePreview();
    if (_recPath != null) try { File(_recPath!).deleteSync(); } catch (_) {}
    setState(() { _recPreview = false; _recPath = null; });
  }

  Future<void> _sendPreview() async {
    if (_recPath == null) return;
    final p = _recPath!;
    _disposePreview();
    setState(() { _recPreview = false; _recPath = null; });
    await _send(filePath: p, type: 'audio');
  }

  Future<void> _initPreview(String p) async {
    await _previewPlayer?.dispose();
    _previewPlayer  = AudioPlayer();
    await _previewPlayer!.setFilePath(p);
    _previewDur     = _previewPlayer!.duration ?? Duration.zero;
    _previewPos     = Duration.zero;
    _previewPlaying = false;
    _previewPosSub  = _previewPlayer!.positionStream.listen((pos) {
      if (mounted) setState(() => _previewPos = pos);
    });
    _previewStateSub = _previewPlayer!.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() => _previewPlaying = false);
      }
    });
  }

  void _disposePreview() {
    _previewPosSub?.cancel();
    _previewStateSub?.cancel();
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer  = null;
    _previewPlaying = false;
    _previewPos     = Duration.zero;
    _previewDur     = Duration.zero;
  }

  Future<void> _togglePreview() async {
    if (_previewPlayer == null) return;
    if (_previewPlaying) {
      await _previewPlayer!.pause();
      setState(() => _previewPlaying = false);
    } else {
      if (_previewPlayer!.processingState == ProcessingState.completed) {
        await _previewPlayer!.seek(Duration.zero);
      }
      await _previewPlayer!.play();
      setState(() => _previewPlaying = true);
    }
  }

  Future<void> _playAudio(String id, String src) async {
    try {
      // Mettre en pause tous les autres lecteurs actifs
      for (final e in _players.entries) {
        if (e.key != id && e.value.playing) {
          await e.value.pause();
        }
      }

      if (!_players.containsKey(id)) {
        final player = AudioPlayer();
        _players[id] = player;

        // Écouter les changements d'état pour rebuild
        player.playerStateStream.listen((s) {
          if (mounted) setState(() {});
        });
        // Écouter la durée (mise à jour dès le chargement)
        player.durationStream.listen((dur) {
          if (dur != null && dur.inMilliseconds > 0) {
            _audioMeta.cacheDuration(id, dur);
            if (mounted) setState(() {});
          }
        });

        // Charger la source
        if (src.startsWith('http')) {
          await player.setUrl(src);
        } else {
          await player.setFilePath(src);
        }

        // Mettre en cache la durée dès qu'elle est disponible
        final dur = player.duration;
        if (dur != null && dur.inMilliseconds > 0) {
          _audioMeta.cacheDuration(id, dur);
          if (mounted) setState(() {});
        }
      }

      final p = _players[id]!;
      if (p.playing) {
        await p.pause();
      } else {
        if (p.processingState == ProcessingState.completed) {
          await p.seek(Duration.zero);
        }
        await p.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showErr("Impossible de lire l'audio");
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Future<void> _initVideo(String id, String url) async {
    if (_vCtrl.containsKey(id) || _vInitializing.contains(id)) return;
    _vInitializing.add(id);
    try {
      final vc = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : VideoPlayerController.file(File(url));
      await vc.initialize();
      final cc = ChewieController(
          videoPlayerController: vc,
          autoPlay: false,
          looping: false,
          aspectRatio: vc.value.aspectRatio,
          errorBuilder: (_, __) =>
              const Center(child: Icon(Icons.error, color: Colors.red)));
      if (mounted) setState(() {
        _vCtrl[id] = vc;
        _cCtrl[id] = cc;
        _vInitializing.remove(id);
      });
    } catch (e) {
      debugPrint('[Video] Erreur init $id: $e');
      if (mounted) setState(() {
        _vInitializing.remove(id);
        _vError.add(id);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD PRINCIPAL
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: _buildAppBar(),
      body: Column(children: [
        if (widget.serviceName != null) _serviceBanner(),
        if (_isSearching) _buildSearchBar(),
        Expanded(child: _buildMsgList()),
        _buildOtherIndicator(),
        _buildInputBar(),
        if (_showEmojiPicker) _buildEmojiPicker(),
      ]),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppConstants.primaryRed,
    foregroundColor: Colors.white,
    elevation: 1,
    leadingWidth: 32,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.pop(context),
      padding: EdgeInsets.zero,
    ),
    titleSpacing: 0,
    title: Consumer<MessageProvider>(builder: (_, pv, __) {
      final isOnline   = pv.getUserOnlineStatus(widget.otherUser.id) ||
          widget.otherUser.isOnline;
      final lastSeen   =
          pv.getUserLastSeen(widget.otherUser.id) ?? widget.otherUser.lastSeen;
      final isTyping   =
          pv.isUserTyping(widget.conversationId, widget.otherUser.id);
      final isRecording =
          pv.isUserRecording(widget.conversationId, widget.otherUser.id);

      return Row(children: [
        Stack(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            backgroundImage: widget.otherUser.photoUrl != null
                ? NetworkImage(widget.otherUser.photoUrl!) : null,
            child: widget.otherUser.photoUrl == null
                ? Text(
                    widget.otherUser.name.isNotEmpty
                        ? widget.otherUser.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryRed))
                : null,
          ),
          if (isOnline)
            Positioned(
              bottom: 1, right: 1,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5))),
            ),
        ]),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.otherUser.name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            if (isRecording)
              Row(children: [
                AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Icon(Icons.mic,
                        size: 11,
                        color: Colors.white70
                            .withOpacity(_pulseAnim.value))),
                const SizedBox(width: 3),
                const Text('enregistre un vocal…',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
              ])
            else if (isTyping)
              const Text('en train d\'écrire…',
                  style: TextStyle(fontSize: 11, color: Colors.white70))
            else if (isOnline)
              const Text('en ligne',
                  style: TextStyle(fontSize: 11, color: Colors.white70))
            else if (lastSeen != null)
              Text(_fmtSeen(lastSeen),
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70)),
          ],
        )),
      ]);
    }),
    actions: [
      IconButton(
        icon: Icon(_isSearching ? Icons.close : Icons.search),
        onPressed: () {
          setState(() {
            if (_isSearching) {
              _isSearching        = false;
              _searchCtrl.clear();
              _searchQuery        = '';
              _searchResults      = [];
              _searchCurrentIndex = -1;
            } else {
              _isSearching = true;
            }
          });
        },
      ),
      IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showOptions),
    ],
  );

  // ── Barre de recherche ────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      color: AppConstants.primaryRed,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20)),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher dans la conversation...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AppConstants.primaryRed),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            '${_searchCurrentIndex + 1}/${_searchResults.length}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up,
                color: Colors.white, size: 20),
            onPressed: () => _navigateSearchResult(false),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 20),
            onPressed: () => _navigateSearchResult(true),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ]),
    );
  }

  // ── Formatage heure "vu à…" ───────────────────────────────────────────────

  String _fmtSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'vu à l\'instant';
    if (diff.inMinutes < 60) return 'vu il y a ${diff.inMinutes} min';
    if (diff.inHours < 24)  return 'vu il y a ${diff.inHours} h';
    return 'vu le ${DateFormat('dd/MM/yy').format(d)}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LISTE DE MESSAGES (scroll intelligent + bouton descendre)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMsgList() {
    return Consumer<MessageProvider>(
      builder: (ctx, pv, _) {
        final msgs = pv.getMessages(widget.conversationId);

        // Pré-charger les durées audio de tous les nouveaux messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _preloadNewAudioDurations(msgs);
        });

        // Scroll auto uniquement si on est déjà en bas
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isAtBottom && _scroll.hasClients) {
            final max = _scroll.position.maxScrollExtent;
            if (_scroll.offset < max - 5) {
              _scroll.animateTo(max,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut);
            }
          }
          _markRead();
          NotificationService()
              .cancelNotification(widget.conversationId);
        });

        if (pv.isLoading && msgs.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppConstants.primaryRed));
        }
        if (msgs.isEmpty) return _buildEmpty();

        return Stack(children: [
          // ── Liste des messages ─────────────────────────────────────
          ListView.builder(
            controller : _scroll,
            padding    : const EdgeInsets.symmetric(
                horizontal: 8, vertical: 10),
            itemCount  : msgs.length,
            itemBuilder: (_, i) {
              bool showDate = i == 0;
              if (i > 0) {
                final prev = msgs[i - 1].createdAt;
                final curr = msgs[i].createdAt;
                showDate = prev.year  != curr.year  ||
                           prev.month != curr.month ||
                           prev.day   != curr.day;
              }
              final isHighlighted = _isSearching &&
                  _searchResults.contains(i) &&
                  _searchQuery.isNotEmpty &&
                  msgs[i].content
                      .toLowerCase()
                      .contains(_searchQuery);
              final isCurrentSearch = _isSearching &&
                  _searchCurrentIndex >= 0 &&
                  _searchCurrentIndex < _searchResults.length &&
                  _searchResults[_searchCurrentIndex] == i;

              return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showDate) _buildDateSep(msgs[i].createdAt),
                    _buildSwipeable(
                        msgs[i], i, isHighlighted, isCurrentSearch),
                  ]);
            },
          ),

          // ── Bouton "descendre" avec badge ──────────────────────────
          if (!_isAtBottom)
            Positioned(
              bottom: 12,
              right : 12,
              child: GestureDetector(
                onTap: () => _scrollBottom(animated: true),
                child: Container(
                  width : 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color     : Colors.white,
                    shape     : BoxShape.circle,
                    boxShadow : [
                      BoxShadow(
                          color     : Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset    : const Offset(0, 2))
                    ],
                  ),
                  child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.keyboard_arrow_down,
                            color: AppConstants.primaryRed, size: 24),
                        // Badge non lus
                        Consumer<MessageProvider>(
                            builder: (_, pv2, __) {
                          final conv = pv2.conversations.firstWhere(
                              (c) => c.id == widget.conversationId,
                              orElse: () => ConversationModel(
                                  id      : '',
                                  otherUser: UserModel(
                                      id: '', name: ''),
                                  updatedAt: DateTime.now()));
                          if (conv.unreadCount == 0) {
                            return const SizedBox.shrink();
                          }
                          return Positioned(
                            top  : 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                  color: AppConstants.primaryRed,
                                  shape: BoxShape.circle),
                              child: Text(
                                '${conv.unreadCount}',
                                style: const TextStyle(
                                    color     : Colors.white,
                                    fontSize  : 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }),
                      ]),
                ),
              ),
            ),
        ]);
      },
    );
  }

  // ── Séparateur de date ────────────────────────────────────────────────────

  Widget _buildDateSep(DateTime msgDate) {
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(msgDate.year, msgDate.month, msgDate.day);
    final diff   = today.difference(msgDay).inDays;

    final label = diff == 0
        ? "Aujourd'hui"
        : diff == 1
            ? 'Hier'
            : DateFormat('dd MMMM yyyy', 'fr_FR').format(msgDate);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color       : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            boxShadow   : [
              BoxShadow(
                  color     : Colors.black.withOpacity(0.06),
                  blurRadius: 3)
            ],
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize  : 12,
                  color     : Color(0xFF3B3B3B),
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  // ── Swipeable (répondre par glissement) ───────────────────────────────────

  Widget _buildSwipeable(
      MessageModel m, int index, bool isHighlighted, bool isCurrentSearch) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! > 300) {
          HapticFeedback.mediumImpact();
          setState(() => _replyTo = m);
          _focus.requestFocus();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isCurrentSearch
            ? BoxDecoration(
                color       : Colors.yellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8))
            : isHighlighted
                ? BoxDecoration(
                    color       : Colors.yellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8))
                : null,
        child: _buildBubble(m),
      ),
    );
  }

  // ── Bulle de message ──────────────────────────────────────────────────────

  Widget _buildBubble(MessageModel m) {
    final isMe  = m.isMe;
    final isErr = m.status == 'error';
    final bg    = isErr
        ? Colors.red[50]!
        : isMe
            ? const Color(0xFFDCF8C6)
            : Colors.white;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: 3, left: isMe ? 55 : 0, right: isMe ? 0 : 55),
        child: Row(
          mainAxisSize     : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar messages reçus
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 2),
                child: CircleAvatar(
                  radius         : 14,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: widget.otherUser.photoUrl != null
                      ? NetworkImage(widget.otherUser.photoUrl!)
                      : null,
                  child: widget.otherUser.photoUrl == null
                      ? Text(
                          widget.otherUser.name.isNotEmpty
                              ? widget.otherUser.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppConstants.primaryRed))
                      : null,
                ),
              ),
            Flexible(
              child: GestureDetector(
                onLongPress: () => _msgMenu(m),
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color       : bg,
                    borderRadius: BorderRadius.only(
                      topLeft    : const Radius.circular(14),
                      topRight   : const Radius.circular(14),
                      bottomLeft : isMe
                          ? const Radius.circular(14)
                          : const Radius.circular(3),
                      bottomRight: isMe
                          ? const Radius.circular(3)
                          : const Radius.circular(14),
                    ),
                    border   : isErr ? Border.all(color: Colors.red) : null,
                    boxShadow: [
                      BoxShadow(
                          color     : Colors.black.withOpacity(0.07),
                          blurRadius: 3,
                          offset    : const Offset(0, 1))
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.replyTo != null)
                          _buildReplyPreview(m.replyTo!),
                        _buildMsgContent(m),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize     : MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(m.createdAt),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isMe
                                      ? const Color(0xFF6E8B6E)
                                      : Colors.grey[500]),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 3),
                              _statusIcon(m),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview(ReplyToModel reply) {
    return Container(
      margin   : const EdgeInsets.only(bottom: 6),
      padding  : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color       : Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border      : const Border(
            left: BorderSide(
                color: AppConstants.primaryRed, width: 3)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reply.senderName,
                style: const TextStyle(
                    fontSize  : 11,
                    fontWeight: FontWeight.bold,
                    color     : AppConstants.primaryRed)),
            const SizedBox(height: 2),
            Text(
              reply.type == 'text'
                  ? reply.content
                  : '${_typeLabel(reply.type)}',
              maxLines : 2,
              overflow : TextOverflow.ellipsis,
              style    : TextStyle(
                  fontSize: 12, color: Colors.grey[700]),
            ),
          ]),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'image'   : return 'Image';
      case 'video'   : return 'Vidéo';
      case 'audio'   :
      case 'vocal'   : return 'Message vocal';
      case 'document': return 'Document';
      case 'location': return 'Localisation';
      default        : return 'Message';
    }
  }

  Widget _statusIcon(MessageModel m) {
    if (m.status == 'sending')
      return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Color(0xFF6E8B6E)));
    if (m.status == 'error')
      return const Icon(Icons.error_outline,
          size: 13, color: Colors.red);
    if (m.readAt != null)
      return const Icon(Icons.done_all,
          size: 14, color: Color(0xFF53BDEB));
    return const Icon(Icons.done,
        size: 14, color: Color(0xFF6E8B6E));
  }

  // ── Contenu du message ────────────────────────────────────────────────────

  Widget _buildMsgContent(MessageModel m) {
    switch (m.type) {
      case 'image'   : return _buildImgContent(m);
      case 'video'   : return _buildVidContent(m);
      case 'location': return _buildLocContent(m);
      case 'audio'   :
      case 'vocal'   : return _buildAudioContent(m);
      case 'document': return _buildDocContent(m);
      default:
        if (m.content.isEmpty) return const SizedBox.shrink();
        return Text(m.content,
            style: const TextStyle(
                fontSize: 14.5,
                color   : Color(0xFF2D2D2D),
                height  : 1.35));
    }
  }

  Widget _buildImgContent(MessageModel m) {
    // Priorité : fichier local → URL réseau
    final src = m.effectiveMediaUrl;

    if (src == null || src.isEmpty) {
      return Container(
          width : 220,
          height: 180,
          color : Colors.grey[200],
          child : const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    // Chemin local (fichier déjà téléchargé ou en cours d'upload)
    if (!src.startsWith('http')) {
      final file = File(src);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(children: [
          Image.file(
            file,
            width : 220,
            height: 180,
            fit   : BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                width : 220,
                height: 180,
                color : Colors.grey[200],
                child : const Icon(Icons.broken_image)),
          ),
          // Overlay "envoi en cours" seulement si le message est encore en statut sending
          if (m.status == 'sending')
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              ),
            ),
        ]),
      );
    }

    final heroTag = 'img_${m.id}';
    return GestureDetector(
      onTap: () => ImageViewerModal.show(context, src, heroTag: heroTag),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Image.network(
                src,
                width : 220,
                height: 180,
                fit   : BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        width : 220,
                        height: 180,
                        color : Colors.grey[200],
                        child : const Center(
                            child: CircularProgressIndicator(strokeWidth: 2))),
                errorBuilder: (_, __, ___) => Container(
                    width : 220,
                    height: 180,
                    color : Colors.grey[200],
                    child : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.grey),
                        SizedBox(height: 4),
                        Text('Image indisponible',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    )),
              ),
              Positioned(
                bottom: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.zoom_out_map,
                      color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVidContent(MessageModel m) {
    // Priorité : fichier local → URL réseau
    final src = m.effectiveMediaUrl;

    if (src == null || src.isEmpty) {
      return _videoPlaceholder('Envoi…');
    }

    // Fichier local ou envoi en cours
    if (!src.startsWith('http')) {
      if (m.status == 'sending') return _videoPlaceholder('Envoi en cours…');
      // Fichier local disponible → lecture directe
      if (!_cCtrl.containsKey(m.id)) {
        _initVideoFromPath(m.id, src);
        return _videoPlaceholder('Chargement…');
      }
    } else {
      // Erreur d'initialisation réseau
      if (_vError.contains(m.id)) {
        return GestureDetector(
          onTap: () {
            setState(() => _vError.remove(m.id));
            _initVideo(m.id, src);
          },
          child: _videoError(),
        );
      }
      if (!_cCtrl.containsKey(m.id)) {
        _initVideo(m.id, src);
        return _videoPlaceholder('Chargement…');
      }
    }

    return GestureDetector(
      onTap: () => VideoViewerModal.show(context, src),
      child: SizedBox(
        width : 220,
        height: 160,
        child : ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Chewie(controller: _cCtrl[m.id]!),
              Positioned(
                bottom: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.fullscreen,
                      color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoPlaceholder(String label) => Container(
      width     : 220,
      height    : 160,
      decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]));

  Widget _videoError() => Container(
      width     : 220,
      height    : 160,
      decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8)),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, color: Colors.red, size: 36),
        SizedBox(height: 6),
        Text('Impossible de charger la vidéo',
            style: TextStyle(color: Colors.white70, fontSize: 11)),
        SizedBox(height: 4),
        Text('Appuyer pour réessayer',
            style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]));

  /// Initialise un lecteur vidéo depuis un chemin fichier local.
  Future<void> _initVideoFromPath(String id, String path) async {
    if (_vCtrl.containsKey(id) || _vInitializing.contains(id)) return;
    _vInitializing.add(id);
    try {
      final vc = VideoPlayerController.file(File(path));
      await vc.initialize();
      final cc = ChewieController(
          videoPlayerController: vc,
          autoPlay: false,
          looping: false,
          aspectRatio: vc.value.aspectRatio,
          errorBuilder: (_, __) =>
              const Center(child: Icon(Icons.error, color: Colors.red)));
      if (mounted) setState(() {
        _vCtrl[id] = vc;
        _cCtrl[id] = cc;
        _vInitializing.remove(id);
      });
    } catch (e) {
      if (mounted) setState(() {
        _vInitializing.remove(id);
        _vError.add(id);
      });
    }
  }

  Widget _buildLocContent(MessageModel m) {
    final hasCoords = m.latitude != null && m.longitude != null;
    return GestureDetector(
      onTap: () =>
          hasCoords ? _openLoc(m.latitude!, m.longitude!) : null,
      child: Container(
        width     : 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow   : [
            BoxShadow(
                color     : Colors.black.withOpacity(0.12),
                blurRadius: 8,
                offset    : const Offset(0, 3))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (hasCoords)
              Stack(children: [
                SizedBox(
                  height: 130,
                  width : double.infinity,
                  child : Image.network(
                    'https://staticmap.openstreetmap.de/staticmap.php'
                    '?center=${m.latitude},${m.longitude}'
                    '&zoom=15&size=400x200'
                    '&markers=${m.latitude},${m.longitude},red',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 130,
                      color : const Color(0xFFE8F4F0),
                      child : Center(
                          child: Icon(Icons.map_outlined,
                              size: 40,
                              color: Colors.teal[300])),
                    ),
                  ),
                ),
                Positioned(
                    bottom: 0,
                    left  : 0,
                    right : 0,
                    child : Container(
                        height    : 40,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin : Alignment.topCenter,
                                end   : Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.35)
                                ])))),
                const Positioned.fill(
                    child: Center(child: _MapPin())),
                Positioned(
                    bottom: 8,
                    right : 8,
                    child : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color    : Colors.white,
                            borderRadius:
                                BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black
                                      .withOpacity(0.15),
                                  blurRadius: 4)
                            ]),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.directions,
                                  size : 12,
                                  color: Colors.blue[700]),
                              const SizedBox(width: 3),
                              Text('Itinéraire',
                                  style: TextStyle(
                                      fontSize  : 10,
                                      fontWeight:
                                          FontWeight.w600,
                                      color: Colors.blue[700])),
                            ]))),
              ])
            else
              Container(
                  height: 80,
                  color : const Color(0xFFE8F4F0),
                  child : Center(
                      child: Icon(Icons.map_outlined,
                          size : 36,
                          color: Colors.teal[300]))),

            Container(
              color  : m.isMe
                  ? const Color(0xFFDCF8C6)
                  : Colors.white,
              padding:
                  const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: AppConstants.primaryRed
                          .withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.location_on,
                      size : 16,
                      color: AppConstants.primaryRed),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                      Text('Position partagée',
                          style: TextStyle(
                              fontSize  : 11,
                              fontWeight: FontWeight.w700,
                              color     : Colors.grey[700])),
                      if (m.content.isNotEmpty)
                        Text(m.content,
                            maxLines : 2,
                            overflow : TextOverflow.ellipsis,
                            style    : TextStyle(
                                fontSize: 11,
                                color   : Colors.grey[500],
                                height  : 1.3)),
                    ])),
                Icon(Icons.open_in_new,
                    size: 14, color: Colors.grey[400]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildAudioContent(MessageModel m) {
    // Priorité : fichier local → URL réseau
    final src = m.effectiveMediaUrl;

    // En cours d'envoi — pas encore d'URL
    if (src == null || src.isEmpty) {
      return _audioSendingWidget();
    }

    // Pré-charger la durée dès l'affichage de la bulle (fire-and-forget)
    _audioMeta.preload(m.id, src, notify: () {
      if (mounted) setState(() {});
    });

    final player  = _players[m.id];
    final playing = player?.playing ?? false;

    // Durée : depuis le cache (disponible immédiatement) ou depuis le player actif
    final cachedDur = _audioMeta.getDuration(m.id);
    final isMe = m.isMe;
    final accent = isMe ? const Color(0xFF25D366) : AppConstants.primaryRed;

    return StreamBuilder<Duration>(
      stream : player?.positionStream ?? const Stream.empty(),
      builder: (_, posSnap) {
        final pos = posSnap.data ?? Duration.zero;

        // Durée finale : player actif (précis) > cache > zéro
        final dur = player?.duration ?? cachedDur ?? Duration.zero;
        final pct = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        final isCompleted =
            player?.processingState == ProcessingState.completed;

        return Container(
          width  : 220,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child  : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Bouton play/pause ─────────────────────────────────────────
              GestureDetector(
                onTap: () => _playAudio(m.id, src),
                onLongPress: () => AudioPlayerModal.show(
                  context,
                  url           : src,
                  senderName    : widget.otherUser.name,
                  isMe          : isMe,
                  senderPhotoUrl: isMe ? null : widget.otherUser.photoUrl,
                ),
                child: AnimatedContainer(
                  duration  : const Duration(milliseconds: 150),
                  width     : 40,
                  height    : 40,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child     : Icon(
                    playing
                        ? Icons.pause_rounded
                        : isCompleted
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size : 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ── Barre de progression + durée ──────────────────────────────
              Expanded(
                child: Column(
                  mainAxisSize     : MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Waveform-like slider
                    SizedBox(
                      height: 28,
                      child : SliderTheme(
                        data : SliderThemeData(
                          thumbShape        : const RoundSliderThumbShape(
                              enabledThumbRadius: 5),
                          trackHeight       : 3,
                          thumbColor        : accent,
                          activeTrackColor  : accent,
                          inactiveTrackColor: isMe
                              ? Colors.white.withAlpha(100)
                              : Colors.grey[300],
                          overlayShape      : const RoundSliderOverlayShape(
                              overlayRadius: 12),
                          trackShape        : const RoundedRectSliderTrackShape(),
                        ),
                        child: Slider(
                          value    : pct.toDouble(),
                          onChanged: (v) {
                            if (player != null && dur.inMilliseconds > 0) {
                              player.seek(Duration(
                                  milliseconds:
                                      (v * dur.inMilliseconds).toInt()));
                            }
                          },
                        ),
                      ),
                    ),

                    // Durée : temps écoulé à gauche, durée totale à droite
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child  : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            playing || pos.inMilliseconds > 0
                                ? _fmt(pos)
                                : '',
                            style: TextStyle(
                                fontSize: 10,
                                color   : isMe
                                    ? Colors.white70
                                    : Colors.grey[600]),
                          ),
                          Row(children: [
                            // Petit indicateur de chargement si durée pas encore dispo
                            if (dur == Duration.zero &&
                                _audioMeta.isLoading(m.id))
                              SizedBox(
                                width : 8,
                                height: 8,
                                child : CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: isMe
                                      ? Colors.white60
                                      : Colors.grey[400],
                                ),
                              )
                            else
                              Text(
                                _fmt(dur),
                                style: TextStyle(
                                    fontSize: 10,
                                    color   : isMe
                                        ? Colors.white70
                                        : Colors.grey[600]),
                              ),
                            // Icône hors-ligne si fichier local dispo
                            if (m.hasLocalMedia) ...[
                              const SizedBox(width: 3),
                              Icon(Icons.offline_pin,
                                  size : 9,
                                  color: isMe
                                      ? Colors.white54
                                      : Colors.green[600]),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Placeholder pendant l'envoi d'un audio
  Widget _audioSendingWidget() => SizedBox(
    width: 220,
    child: Row(children: [
      Container(
        width : 40,
        height: 40,
        decoration: BoxDecoration(
            color: Colors.grey[300], shape: BoxShape.circle),
        child: const Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.grey),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height    : 3,
            decoration: BoxDecoration(
                color       : Colors.grey[300],
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Text('Envoi en cours…',
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      )),
    ]),
  );

  Widget _buildDocContent(MessageModel m) {
    // Priorité : fichier local → URL réseau
    final src = m.effectiveMediaUrl;

    if (src == null || src.isEmpty) {
      return Container(
        width  : 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color       : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border      : Border.all(color: Colors.grey[300]!)),
        child: Row(children: [
          const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Envoi en cours…',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1)),
        ]),
      );
    }

    final fn  = src.split('/').last.split('?').first;
    final ext = fn.split('.').last.toLowerCase();
    final ico = ext == 'pdf'
        ? Icons.picture_as_pdf
        : (ext == 'doc' || ext == 'docx')
            ? Icons.description
            : (ext == 'xls' || ext == 'xlsx')
                ? Icons.table_chart
                : Icons.insert_drive_file;
    final color = ext == 'pdf'
        ? Colors.red
        : (ext == 'doc' || ext == 'docx')
            ? const Color(0xFF2B579A)
            : (ext == 'xls' || ext == 'xlsx')
                ? const Color(0xFF217346)
                : Colors.grey[700]!;

    // Pour l'ouverture : préférer le chemin local, sinon l'URL réseau
    final openSrc = m.hasLocalMedia ? src : (m.fileUrl ?? src);

    return GestureDetector(
      onTap: () => DocumentViewerModal.show(context, openSrc, fn),
      child: Container(
        width    : 210,
        padding  : const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color       : Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border      : Border.all(color: Colors.grey[300]!),
            boxShadow   : [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4, offset: const Offset(0, 1))
            ]),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(ico, color: color, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(fn,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Text(ext.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w600)),
                  if (m.hasLocalMedia) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.offline_pin, size: 10, color: Colors.green[600]),
                  ],
                ]),
              ])),
          Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
        ]),
      ),
    );
  }

  // ── Indicateur typing / recording (WhatsApp-like) ────────────────────────

  Widget _buildOtherIndicator() {
    return Consumer<MessageProvider>(builder: (_, pv, __) {
      final typing    = pv.isUserTyping(widget.conversationId, widget.otherUser.id);
      final recording = pv.isUserRecording(widget.conversationId, widget.otherUser.id);
      final show      = typing || recording;

      // AnimatedSize = apparition / disparition fluide sans saut
      return AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve   : Curves.easeOut,
        child   : show
            ? Container(
                width  : double.infinity,
                color  : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child  : Row(
                  mainAxisSize: MainAxisSize.min,
                  children    : [
                    if (recording) ...[
                      // Cercle rouge pulsant
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder  : (_, __) => Container(
                          width : 8, height: 8,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              Colors.red.withAlpha(100),
                              Colors.red,
                              _pulseAnim.value,
                            )!,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Icône micro animée
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder  : (_, __) => Icon(
                          Icons.mic,
                          size : 14,
                          color: Color.lerp(
                            Colors.red.withAlpha(120),
                            Colors.red,
                            _pulseAnim.value,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.otherUser.name} enregistre un vocal…',
                        style: const TextStyle(
                          fontSize : 12.5,
                          color    : Colors.red,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else ...[
                      // Trois points animés style WhatsApp
                      _TypingDotsWidget(animation: _pulseAnim),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.otherUser.name} est en train d\'écrire…',
                        style: TextStyle(
                          fontSize : 12.5,
                          color    : Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : const SizedBox.shrink(),
      );
    });
  }

  /// Trois points animés en cascade — délégué à un widget dédié
  /// pour éviter de reconstruire toute la bulle à chaque frame.
  // ignore: unused_element
  Widget _typingDots() => _TypingDotsWidget(animation: _pulseAnim);

  // ═══════════════════════════════════════════════════════════════════════════
  //  BARRE D'INPUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputBar() => Container(
    color  : const Color(0xFFF0F2F5),
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
    child  : Column(mainAxisSize: MainAxisSize.min, children: [
      if (_recPreview) _buildPreviewBar(),
      if (_recActive && _recLocked) _buildLockedRecBar(),
      if (_replyTo != null && !_isEditing) _buildReplyBanner(),
      if (_isEditing && _editingMessage != null) _buildEditBanner(),
      if (!_recPreview)
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _buildAttachBtn(),
          const SizedBox(width: 4),
          Expanded(child: _buildTextField()),
          const SizedBox(width: 6),
          _buildSendOrMic(),
        ]),
      if (_recActive && !_recLocked) _buildActiveRecBar(),
    ]),
  );

  Widget _buildReplyBanner() {
    return Container(
      margin   : const EdgeInsets.only(bottom: 6),
      padding  : const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
            left: BorderSide(
                color: AppConstants.primaryRed, width: 3)),
      ),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text(
              'Répondre à ${_replyTo!.isMe ? "vous-même" : widget.otherUser.name}',
              style: const TextStyle(
                  fontSize  : 11,
                  fontWeight: FontWeight.bold,
                  color     : AppConstants.primaryRed)),
          const SizedBox(height: 2),
          Text(
            _replyTo!.type == 'text'
                ? _replyTo!.content
                : '📎 ${_typeLabel(_replyTo!.type)}',
            maxLines : 1,
            overflow : TextOverflow.ellipsis,
            style    : TextStyle(
                fontSize: 12, color: Colors.grey[600]),
          ),
        ])),
        IconButton(
          icon       : const Icon(Icons.close, size: 18),
          onPressed  : () => setState(() => _replyTo = null),
          padding    : EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _buildEditBanner() {
    return Container(
      margin   : const EdgeInsets.only(bottom: 6),
      padding  : const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: const Border(
            left: BorderSide(color: Colors.blue, width: 3)),
      ),
      child: Row(children: [
        const Icon(Icons.edit, size: 16, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          const Text('Modifier le message',
              style: TextStyle(
                  fontSize  : 11,
                  fontWeight: FontWeight.bold,
                  color     : Colors.blue)),
          Text(_editingMessage!.content,
              maxLines : 1,
              overflow : TextOverflow.ellipsis,
              style    : TextStyle(
                  fontSize: 12, color: Colors.grey[600])),
        ])),
        IconButton(
          icon       : const Icon(Icons.close,
              size: 18, color: Colors.blue),
          onPressed  : _cancelEdit,
          padding    : EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _buildTextField() => Container(
    decoration: BoxDecoration(
        color    : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color     : Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset    : const Offset(0, 1))
        ]),
    child: Row(children: [
      const SizedBox(width: 14),
      Expanded(
          child: TextField(
        controller     : _msgCtrl,
        focusNode      : _focus,
        minLines       : 1,
        maxLines       : 5,
        keyboardType   : TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        enabled        : !_sending && !_recActive && !_recPreview,
        style          : const TextStyle(
            fontSize: 15, color: Color(0xFF2D2D2D)),
        decoration: InputDecoration(
          hintText : _isEditing
              ? 'Modifier le message...'
              : 'Message',
          hintStyle: TextStyle(
              color: Colors.grey[400], fontSize: 15),
          border        : InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10),
        ),
      )),
      IconButton(
          icon: Icon(
            _showEmojiPicker
                ? Icons.keyboard
                : Icons.emoji_emotions_outlined,
            color: _showEmojiPicker
                ? AppConstants.primaryRed
                : Colors.grey[500],
            size: 22,
          ),
          onPressed: () {
            setState(
                () => _showEmojiPicker = !_showEmojiPicker);
            if (_showEmojiPicker) {
              _focus.unfocus();
            } else {
              _focus.requestFocus();
            }
          },
          padding    : EdgeInsets.zero,
          constraints: const BoxConstraints(
              minWidth: 36, minHeight: 36)),
      const SizedBox(width: 4),
    ]),
  );

  Widget _buildEmojiPicker() {
    return Container(
      height: 200,
      color : Colors.white,
      child : Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color : Colors.grey[100],
            border: Border(
                top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(children: [
            const Text('Emojis fréquents',
                style: TextStyle(
                    fontSize  : 13,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon       : const Icon(Icons.close, size: 18),
              onPressed  : () =>
                  setState(() => _showEmojiPicker = false),
              padding    : EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount : 10,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount  : _frequentEmojis.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () {
                final emoji     = _frequentEmojis[i];
                final currentText = _msgCtrl.text;
                final selection = _msgCtrl.selection;
                final newText   = currentText.substring(
                        0, selection.start) +
                    emoji +
                    currentText.substring(selection.end);
                _msgCtrl.text = newText;
                _msgCtrl.selection =
                    TextSelection.fromPosition(TextPosition(
                        offset:
                            selection.start + emoji.length));
                setState(() => _hasText = true);
              },
              child: Center(
                  child: Text(_frequentEmojis[i],
                      style:
                          const TextStyle(fontSize: 22))),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildAttachBtn() => PopupMenuButton<String>(
    icon: Container(
        width : 44,
        height: 44,
        decoration: const BoxDecoration(
            color: AppConstants.primaryRed,
            shape: BoxShape.circle),
        child: const Icon(Icons.add,
            color: Colors.white, size: 24)),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14)),
    onSelected: (v) {
      switch (v) {
        case 'camera'  : _pickImg(ImageSource.camera);   break;
        case 'gallery' : _pickImg(ImageSource.gallery);  break;
        case 'video'   : _pickVid(ImageSource.gallery);  break;
        case 'document': _pickDoc();                     break;
        case 'location': _sendLoc();                     break;
      }
    },
    itemBuilder: (_) => [
      _mi('camera',   Icons.camera_alt,        const Color(0xFF1DA1F2), 'Photo'),
      _mi('gallery',  Icons.photo,             const Color(0xFF9B59B6), 'Galerie'),
      _mi('video',    Icons.videocam,          const Color(0xFFF39C12), 'Vidéo'),
      _mi('document', Icons.insert_drive_file, const Color(0xFFE74C3C), 'Document'),
      PopupMenuItem(
        value  : 'location',
        enabled: !_sendingLoc,
        child  : Row(children: [
          Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71)
                      .withOpacity(0.15),
                  borderRadius:
                      BorderRadius.circular(8)),
              child: Icon(Icons.location_on,
                  color: const Color(0xFF2ECC71),
                  size : 18)),
          const SizedBox(width: 12),
          Text(_sendingLoc ? 'Envoi…' : 'Localisation',
              style:
                  const TextStyle(fontSize: 14)),
        ])),
    ],
  );

  PopupMenuItem<String> _mi(
          String val, IconData icon, Color c, String label) =>
      PopupMenuItem(
          value: val,
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color       : c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: c, size: 18)),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(fontSize: 14)),
          ]));

  Widget _buildSendOrMic() {
    if (_hasText || _sending || _isEditing) {
      return GestureDetector(
        onTap: _sending ? null : () => _send(content: _msgCtrl.text),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width   : 48,
          height  : 48,
          decoration: BoxDecoration(
              color    : _sending
                  ? Colors.grey
                  : AppConstants.primaryRed,
              shape    : BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppConstants.primaryRed
                        .withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: _sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child  : CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Icon(
                  _isEditing ? Icons.check : Icons.send,
                  color: Colors.white,
                  size : 22)),
      );
    }
    return _buildMicButton();
  }

  Widget _buildMicButton() {
    return Stack(
      clipBehavior: Clip.none,
      alignment   : Alignment.center,
      children    : [
        // Hint "glisser"
        if (_showSwipeHint && !_recActive)
          Positioned(
            bottom: 56,
            child : TweenAnimationBuilder<double>(
              tween   : Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder : (_, v, child) => Opacity(
                  opacity: v,
                  child  : Transform.translate(
                      offset: Offset(0, -8 * v),
                      child : child)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color       : Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children    : [
                  Icon(Icons.keyboard_arrow_up,
                      color: Colors.white, size: 14),
                  SizedBox(width: 3),
                  Text('Maintenir & glisser',
                      style: TextStyle(
                          color   : Colors.white,
                          fontSize: 10)),
                ]),
              ),
            ),
          ),

        // Bouton mic
        GestureDetector(
          key                : _micKey,
          onVerticalDragStart: (d) {
            _micTouchStart = d.globalPosition;
            _startRec();
          },
          onVerticalDragUpdate: (d) {
            if (_micTouchStart == null || !_recActive) return;
            final dy = d.globalPosition.dy - _micTouchStart!.dy;
            final dx = d.globalPosition.dx - _micTouchStart!.dx;
            setState(() { _micDragY = dy; _micDragX = dx; });
            if (dy < _kLockY && !_recLocked) {
              HapticFeedback.mediumImpact();
              setState(() {
                _recLocked = true;
                _micDragX  = 0;
                _micDragY  = 0;
              });
            } else if (dx < _kCancelX) {
              _cancelRec();
              _micTouchStart = null;
            }
          },
          onVerticalDragEnd: (_) {
            if (!_recActive) { _micTouchStart = null; return; }
            if (!_recLocked) _stopForPreview();
            _micTouchStart = null;
          },
          onVerticalDragCancel: () {
            if (_recActive && !_recLocked) _cancelRec();
            _micTouchStart = null;
          },
          child: AnimatedBuilder(
            animation: _micScaleAnim,
            builder  : (_, __) => Transform.scale(
              scale: _micScaleAnim.value,
              child: AnimatedContainer(
                duration : const Duration(milliseconds: 200),
                width    : _recActive ? 56 : 48,
                height   : _recActive ? 56 : 48,
                decoration: BoxDecoration(
                    color    : _recActive
                        ? (_micDragX < _kCancelX
                            ? Colors.red
                            : const Color(0xFF25D366))
                        : AppConstants.primaryRed,
                    shape    : BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: (_recActive
                                  ? const Color(0xFF25D366)
                                  : AppConstants.primaryRed)
                              .withOpacity(0.45),
                          blurRadius: _recActive ? 16 : 6,
                          spreadRadius: _recActive ? 3 : 0,
                          offset: const Offset(0, 2))
                    ]),
                child: _recActive
                    ? (_micDragX < _kCancelX
                        ? const Icon(Icons.delete_outline,
                            color: Colors.white, size: 24)
                        : AnimatedBuilder(
                            animation: _pulseAnim,
                            builder  : (_, __) => Icon(
                                Icons.mic,
                                color: Colors.white.withOpacity(
                                    0.6 +
                                        0.4 *
                                            _pulseAnim.value),
                                size: 24)))
                    : const Icon(Icons.mic,
                        color: Colors.white, size: 24),
              ),
            ),
          ),
        ),

        // Indicateur verrou
        if (_recActive && !_recLocked && _micDragY < -10)
          Positioned(
            bottom: 60,
            child : Opacity(
              opacity: ((-_micDragY - 10) / 60).clamp(0.0, 1.0),
              child  : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color    : Colors.white,
                    shape    : BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 6)
                    ]),
                child: Icon(Icons.lock_outline,
                    size : 16,
                    color: _micDragY < _kLockY
                        ? Colors.green
                        : Colors.grey[600]),
              ),
            ),
          ),

        // Indicateur annuler
        if (_recActive && !_recLocked && _micDragX < -10)
          Positioned(
            right: 58,
            child: Opacity(
              opacity: ((-_micDragX - 10) / 60).clamp(0.0, 1.0),
              child  : Row(
                  mainAxisSize: MainAxisSize.min,
                  children    : [
                Icon(Icons.chevron_left,
                    color: _micDragX < _kCancelX
                        ? Colors.red
                        : Colors.grey[600],
                    size: 20),
                Text('Annuler',
                    style: TextStyle(
                        fontSize: 11,
                        color   : _micDragX < _kCancelX
                            ? Colors.red
                            : Colors.grey[600])),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveRecBar() {
    return AnimatedContainer(
      duration : const Duration(milliseconds: 200),
      margin   : const EdgeInsets.only(top: 6),
      padding  : const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color    : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color     : Colors.black.withOpacity(0.07),
                blurRadius: 6)
          ]),
      child: Row(children: [
        Row(children: [
          AnimatedBuilder(
              animation: _pulseAnim,
              builder  : (_, __) => Container(
                  width : 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: Colors.red.withOpacity(
                          0.5 + 0.5 * _pulseAnim.value),
                      shape: BoxShape.circle))),
          const SizedBox(width: 6),
          Text(_fmt(_recDuration),
              style: const TextStyle(
                  fontSize  : 14,
                  fontWeight: FontWeight.w700,
                  color     : Color(0xFF2D2D2D))),
        ]),
        const SizedBox(width: 12),
        Expanded(child: _buildWaveform()),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: _cancelRec,
            child: Icon(Icons.close,
                color: Colors.grey[500], size: 20)),
      ]),
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 32,
      child : AnimatedBuilder(
        animation: _waveCtrl,
        builder  : (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _waveformBars.reversed
              .take(28)
              .toList()
              .reversed
              .map((amp) {
            final h = (4 + amp * 26).clamp(4.0, 30.0);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 0.8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  height  : h,
                  decoration: BoxDecoration(
                    color: amp > 0.5
                        ? const Color(0xFF25D366)
                        : const Color(0xFF25D366)
                            .withOpacity(0.4 + amp * 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLockedRecBar() {
    return Container(
      margin   : const EdgeInsets.only(bottom: 8),
      padding  : const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color    : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color     : Colors.black.withOpacity(0.07),
                blurRadius: 6)
          ]),
      child: Row(children: [
        AnimatedBuilder(
            animation: _pulseAnim,
            builder  : (_, __) => Container(
                width : 8,
                height: 8,
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(
                        0.5 + 0.5 * _pulseAnim.value),
                    shape: BoxShape.circle))),
        const SizedBox(width: 8),
        Text(_fmt(_recDuration),
            style: const TextStyle(
                fontSize  : 15,
                fontWeight: FontWeight.bold,
                color     : Color(0xFF2D2D2D))),
        const SizedBox(width: 8),
        Expanded(child: _buildWaveform()),
        const SizedBox(width: 8),
        GestureDetector(
            onTap : _cancelRec,
            child : Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color       : Colors.red[50],
                    borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.delete_outline,
                    color: Colors.red[600], size: 18))),
        const SizedBox(width: 8),
        GestureDetector(
            onTap : _stopForPreview,
            child : Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                    color: AppConstants.primaryRed,
                    shape: BoxShape.circle),
                child: const Icon(Icons.send,
                    color: Colors.white, size: 18))),
      ]),
    );
  }

  Widget _buildPreviewBar() {
    final pct = _previewDur.inMilliseconds > 0
        ? (_previewPos.inMilliseconds / _previewDur.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    return Container(
      margin   : const EdgeInsets.only(bottom: 8),
      padding  : const EdgeInsets.symmetric(
          horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
          color    : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border   : Border.all(
              color: AppConstants.primaryRed.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
                color     : Colors.black.withOpacity(0.06),
                blurRadius: 6)
          ]),
      child: Row(children: [
        GestureDetector(
            onTap : _cancelPreview,
            child : Container(
                width : 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Colors.red[50],
                    shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 18))),
        const SizedBox(width: 8),
        GestureDetector(
            onTap : _togglePreview,
            child : Container(
                width : 42,
                height: 42,
                decoration: const BoxDecoration(
                    color: AppConstants.primaryRed,
                    shape: BoxShape.circle),
                child: Icon(
                    _previewPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size : 24))),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children    : [
          SliderTheme(
            data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6),
                trackHeight       : 3,
                thumbColor        : AppConstants.primaryRed,
                activeTrackColor  : AppConstants.primaryRed,
                inactiveTrackColor: Colors.grey[300]),
            child: Slider(
                value    : pct.toDouble(),
                onChanged: (v) => _previewPlayer?.seek(Duration(
                    milliseconds: (v *
                            _previewDur.inMilliseconds)
                        .toInt()))),
          ),
          Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4),
              child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                Text(_fmt(_previewPos),
                    style: TextStyle(
                        fontSize: 10,
                        color   : Colors.grey[600])),
                Text(_fmt(_previewDur),
                    style: TextStyle(
                        fontSize: 10,
                        color   : Colors.grey[600])),
              ])),
        ])),
        const SizedBox(width: 10),
        GestureDetector(
            onTap : _sendPreview,
            child : Container(
                width : 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle),
                child: const Icon(Icons.send,
                    color: Colors.white, size: 22))),
      ]),
    );
  }

  // ── Menu contextuel message ───────────────────────────────────────────────

  void _msgMenu(MessageModel m) => showModalBottomSheet(
      context: context,
      shape  : const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children    : [
            const SizedBox(height: 8),
            Container(
                width : 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            ListTile(
                leading : const Icon(Icons.reply,
                    color: AppConstants.primaryRed),
                title   : const Text('Répondre'),
                onTap   : () {
                  Navigator.pop(context);
                  setState(() {
                    _replyTo  = m;
                    _isEditing = false;
                  });
                  _focus.requestFocus();
                }),
            ListTile(
                leading: const Icon(Icons.copy_outlined),
                title  : const Text('Copier'),
                onTap  : () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: m.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content : Text('Copié'),
                          duration: Duration(seconds: 1)));
                }),
            if (_canEdit(m))
              ListTile(
                  leading  : const Icon(Icons.edit_outlined,
                      color: Colors.blue),
                  title    : const Text('Modifier'),
                  subtitle : const Text(
                      'Disponible pendant 15 min',
                      style: TextStyle(fontSize: 11)),
                  onTap    : () {
                    Navigator.pop(context);
                    _startEdit(m);
                  }),
            if (m.isMe)
              ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Colors.red),
                  title  : const Text('Supprimer',
                      style: TextStyle(color: Colors.red)),
                  onTap  : () {
                    Navigator.pop(context);
                    _deleteMessage(m);
                  }),
          ])));

  void _showOptions() => showModalBottomSheet(
      context: context,
      shape  : const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
              mainAxisSize: MainAxisSize.min,
              children    : [
            const SizedBox(height: 8),
            ListTile(
                leading: const Icon(Icons.search,
                    color: AppConstants.primaryRed),
                title  : const Text(
                    'Rechercher dans la conversation'),
                onTap  : () {
                  Navigator.pop(context);
                  setState(() => _isSearching = true);
                }),
            ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.red),
                title  : const Text('Supprimer la conversation',
                    style: TextStyle(color: Colors.red)),
                onTap  : () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      shape  : RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(16)),
                      title  : const Text(
                          'Supprimer la conversation'),
                      content: Text(
                          'Supprimer la conversation avec ${widget.otherUser.name} ?'),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(context, false),
                            child: const Text('Annuler')),
                        ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white),
                            child: const Text('Oui')),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    // Afficher un indicateur de chargement
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(
                        child: CircularProgressIndicator(
                            color: AppConstants.primaryRed),
                      ),
                    );

                    final ok = await MessageService()
                        .deleteConversation(widget.conversationId);

                    if (!mounted) return;
                    // Fermer le loader
                    Navigator.pop(context);

                    if (ok) {
                      // Fermer le ChatScreen en passant le résultat
                      // à MessagesScreen via Navigator.pop
                      Navigator.pop(context, 'deleted');
                    } else {
                      _showErr('Erreur lors de la suppression');
                    }
                  }
                }),
          ]));

  // ── Écran vide ────────────────────────────────────────────────────────────

  Widget _buildEmpty() => Center(
    child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children         : [
      Container(
          padding   : const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              shape: BoxShape.circle),
          child: Icon(Icons.chat_bubble_outline,
              size: 52, color: Colors.grey[400])),
      const SizedBox(height: 16),
      Text('Aucun message',
          style: TextStyle(
              fontSize  : 17,
              fontWeight: FontWeight.bold,
              color     : Colors.grey[600])),
      const SizedBox(height: 6),
      Text('Envoyez votre premier message',
          style:
              TextStyle(fontSize: 13, color: Colors.grey[500])),
    ]),
  );

  Widget _serviceBanner() => Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 14, vertical: 7),
    color: Colors.orange[50],
    child: Row(children: [
      Icon(Icons.info_outline,
          size: 14, color: Colors.orange[700]),
      const SizedBox(width: 8),
      Expanded(
          child: Text('À propos de : ${widget.serviceName}',
              style: TextStyle(
                  fontSize: 12,
                  color   : Colors.orange[700]))),
    ]),
  );

  // ── Ouverture URLs / images / carte ───────────────────────────────────────

  // _openImg est désormais géré par ImageViewerModal.show() dans _buildImgContent

  Future<void> _openLoc(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content        : Text(msg),
      backgroundColor: Colors.red[700],
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Widget TYPING DOTS — trois points WhatsApp animés en cascade
// ═══════════════════════════════════════════════════════════════════════════

class _TypingDotsWidget extends StatelessWidget {
  final Animation<double> animation;
  const _TypingDotsWidget({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder  : (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children    : List.generate(3, (i) {
          // Chaque point est en avance de 0.33 dans le cycle
          final phase = (animation.value + i * 0.33) % 1.0;
          // Courbe en cloche : monte puis redescend
          final scale = 0.6 + 0.4 * (1.0 - (phase * 2 - 1).abs().clamp(0.0, 1.0));
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width : 7 * scale,
            height: 7 * scale,
            decoration: BoxDecoration(
              color: Colors.grey[500],
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Widget PIN de carte
// ═══════════════════════════════════════════════════════════════════════════
class _MapPin extends StatefulWidget {
  const _MapPin();
  @override
  State<_MapPin> createState() => _MapPinState();
}

class _MapPinState extends State<_MapPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync   : this,
        duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0.0, end: -6.0)
        .animate(CurvedAnimation(
            parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder  : (_, __) => Transform.translate(
        offset: Offset(0, _bounce.value),
        child : Column(
            mainAxisSize: MainAxisSize.min,
            children    : [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color    : AppConstants.primaryRed,
                shape    : BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color     : AppConstants.primaryRed
                          .withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2)
                ]),
            child: const Icon(Icons.location_on,
                color: Colors.white, size: 18),
          ),
          Container(
            width : 8,
            height: 4,
            decoration: BoxDecoration(
              color       : Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ]),
      ),
    );
  }
}