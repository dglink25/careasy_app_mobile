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
import '../utils/constants.dart';
import '../services/notification_service.dart';
import '../services/message_polling_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final UserModel otherUser;
  final String? serviceName;
  final String? entrepriseName;

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

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _rec = AudioRecorder();
  final Map<String, AudioPlayer> _players = {};
  final Map<String, VideoPlayerController> _vCtrl = {};
  final Map<String, ChewieController> _cCtrl = {};

  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOSOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  final _storage = const FlutterSecureStorage(aOptions: _androidOptions, iOptions: _iOSOptions);

  bool _sending = false;
  bool _hasText = false;
  bool _sendingLoc = false;
  bool _typingActive = false;
  Timer? _typingTimer;
  int _lastMsgCount = 0;

  // === RECHERCHE ===
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<int> _searchResults = []; // indices des messages correspondants
  int _searchCurrentIndex = -1;
  final Map<int, GlobalKey> _msgKeys = {};

  // === RÉPONSE À UN MESSAGE ===
  MessageModel? _replyTo;

  // === MODIFICATION DE MESSAGE ===
  MessageModel? _editingMessage;
  bool _isEditing = false;

  // === EMOJI PICKER ===
  bool _showEmojiPicker = false;

  // Animations
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _micScaleCtrl;
  late Animation<double> _micScaleAnim;
  late AnimationController _waveCtrl;

  // ── Enregistrement vocal ──────────────────────────────────────────────
  bool _recActive = false;
  bool _recLocked = false;
  bool _recPreview = false;
  String? _recPath;
  Duration _recDuration = Duration.zero;
  Timer? _recTimer;

  // Waveform
  final List<double> _waveformBars = List.filled(40, 0.1);
  Timer? _waveformTimer;
  final math.Random _rand = math.Random();
  double _currentAmplitude = 0.0;

  // Swipe micro
  final GlobalKey _micKey = GlobalKey();
  Offset? _micTouchStart;
  double _micDragY = 0.0;
  double _micDragX = 0.0;
  bool _showSwipeHint = false;

  static const double _kCancelX  = -80.0;
  static const double _kLockY    = -80.0;

  // Preview audio
  AudioPlayer? _previewPlayer;
  bool _previewPlaying = false;
  Duration _previewPos = Duration.zero;
  Duration _previewDur = Duration.zero;
  StreamSubscription? _previewPosSub;
  StreamSubscription? _previewStateSub;

  MessageProvider? _msgProvider;

  // Emojis fréquents
  final List<String> _frequentEmojis = [
    '😀','😂','🥰','😍','🤩','😎','🤔','😅','😭','😤',
    '🎉','👍','👎','❤️','🔥','✅','⚡','🙏','💪','😴',
    '🌟','💯','🤝','👏','🥳','😮','🤣','😊','😢','😡',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

    _msgCtrl.addListener(_onTextChanged);
    _searchCtrl.addListener(_onSearchChanged);

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
      MessagePollingService().addMessageListener(
          widget.conversationId, _onPollingMessages);

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showSwipeHint = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showSwipeHint = false);
        });
      });
    });
  }

  void _onPollingMessages(List<MessageModel> msgs) {
    if (!mounted) return;
    setState(() {});
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _searchQuery = q;
      _searchResults = [];
      _searchCurrentIndex = -1;
    });
    if (q.isEmpty) return;

    final msgs = _msgProvider?.getMessages(widget.conversationId) ?? [];
    final results = <int>[];
    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].content.toLowerCase().contains(q)) {
        results.add(i);
      }
    }
    setState(() {
      _searchResults = results.reversed.toList(); // Plus récents en premier
      if (_searchResults.isNotEmpty) {
        _searchCurrentIndex = 0;
        _scrollToMessage(_searchResults[0]);
      }
    });
  }

  void _scrollToMessage(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final msgs = _msgProvider?.getMessages(widget.conversationId) ?? [];
      if (index >= msgs.length) return;
      // Calculer la position approximative
      final total = msgs.length;
      final ratio = index / total;
      final maxExt = _scroll.position.maxScrollExtent;
      _scroll.animateTo(
        maxExt * ratio,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _navigateSearchResult(bool next) {
    if (_searchResults.isEmpty) return;
    setState(() {
      if (next) {
        _searchCurrentIndex = (_searchCurrentIndex + 1) % _searchResults.length;
      } else {
        _searchCurrentIndex = (_searchCurrentIndex - 1 + _searchResults.length) % _searchResults.length;
      }
    });
    _scrollToMessage(_searchResults[_searchCurrentIndex]);
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

  Future<void> _loadMessages() async {
    await _msgProvider?.loadMessages(widget.conversationId);
    _markRead();
    _scrollBottom(animated: false);
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

  void _onTextChanged() {
    final h = _msgCtrl.text.trim().isNotEmpty;
    if (h != _hasText) setState(() => _hasText = h);
    if (h && !_typingActive) {
      _typingActive = true;
      _msgProvider?.sendTypingIndicator(widget.conversationId, true);
    } else if (!h && _typingActive) {
      _typingActive = false;
      _msgProvider?.sendTypingIndicator(widget.conversationId, false);
    }
    _typingTimer?.cancel();
    if (_typingActive) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (_typingActive) {
          _typingActive = false;
          _msgProvider?.sendTypingIndicator(widget.conversationId, false);
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ENVOI / MODIFICATION
  // ═══════════════════════════════════════════════════════════════════

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
    setState(() => _sending = true);
    try {
      final t = type ?? (filePath != null ? _fileType(filePath) : 'text');
      await _msgProvider?.sendMessage(
        widget.conversationId,
        type: lat != null ? 'location' : t,
        content: text.isEmpty ? null : text,
        filePath: filePath,
        latitude: lat,
        longitude: lng,
        replyToId: _replyTo?.id,
      );
      if (type == null || type == 'text') {
        _msgCtrl.clear();
        setState(() { _hasText = false; _replyTo = null; });
      }
      _scrollBottom();
    } catch (_) {
      _showErr("Impossible d'envoyer");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Modification de message ─────────────────────────────────────────
  bool _canEdit(MessageModel msg) {
    if (!msg.isMe) return false;
    if (msg.type != 'text') return false;
    final diff = DateTime.now().difference(msg.createdAt);
    return diff.inMinutes < 15;
  }

  void _startEdit(MessageModel msg) {
    setState(() {
      _editingMessage = msg;
      _isEditing = true;
      _replyTo = null;
    });
    _msgCtrl.text = msg.content;
    _msgCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _msgCtrl.text.length),
    );
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _isEditing = false;
    });
    _msgCtrl.clear();
    setState(() => _hasText = false);
  }

  Future<void> _saveEdit(String newContent) async {
    if (_editingMessage == null || newContent.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final token = await _storage.read(key: 'auth_token');
      final resp = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/messages/${_editingMessage!.id}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'content': newContent.trim()}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        // Mettre à jour localement
        final msgs = _msgProvider?.getMessages(widget.conversationId) ?? [];
        final idx = msgs.indexWhere((m) => m.id == _editingMessage!.id);
        if (idx != -1) {
          final updated = msgs[idx].copyWith(content: newContent.trim());
          // Forcer le refresh via provider
          await _msgProvider?.loadMessages(widget.conversationId);
        }
      } else {
        // Fallback: mettre à jour localement sans serveur
        _showErr('Erreur modification, mis à jour localement');
      }
    } catch (e) {
      _showErr('Erreur de connexion');
    } finally {
      if (mounted) {
        setState(() {
          _editingMessage = null;
          _isEditing = false;
          _sending = false;
          _hasText = false;
        });
        _msgCtrl.clear();
      }
    }
  }

  // ── Suppression de message ──────────────────────────────────────────
  Future<void> _deleteMessage(MessageModel msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer le message'),
        content: const Text('Voulez-vous supprimer ce message ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await _storage.read(key: 'auth_token');
      await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/messages/${msg.id}'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      await _msgProvider?.loadMessages(widget.conversationId);
    } catch (e) {
      _showErr('Erreur suppression');
    }
  }

  String _fileType(String p) {
    final e = p.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(e)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', '3gp'].contains(e)) return 'video';
    if (['mp3', 'm4a', 'aac', 'wav', 'ogg'].contains(e)) return 'audio';
    return 'document';
  }

  Future<void> _pickImg(ImageSource s) async {
    try {
      final f = await _picker.pickImage(source: s, maxWidth: 1024, imageQuality: 80);
      if (f != null) await _send(filePath: f.path, type: 'image');
    } catch (_) { _showErr('Erreur photo'); }
  }

  Future<void> _pickVid(ImageSource s) async {
    try {
      final f = await _picker.pickVideo(source: s, maxDuration: const Duration(minutes: 5));
      if (f != null) await _send(filePath: f.path, type: 'video');
    } catch (_) { _showErr('Erreur vidéo'); }
  }

  Future<void> _pickDoc() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      if (r?.files.single.path != null) {
        await _send(filePath: r!.files.single.path!, type: 'document');
      }
    } catch (_) { _showErr('Erreur document'); }
  }

  Future<void> _sendLoc() async {
    if (_sendingLoc) return;
    setState(() => _sendingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showErr('Permission refusée'); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String addr = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final m = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (m.isNotEmpty) {
          final p = m.first;
          final pts = [
            if (p.street?.isNotEmpty == true) p.street!,
            if (p.locality?.isNotEmpty == true) p.locality!,
            if (p.country?.isNotEmpty == true) p.country!,
          ];
          if (pts.isNotEmpty) addr = pts.join(', ');
        }
      } catch (_) {}
      await _send(content: addr, type: 'location', lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      _showErr('Erreur localisation');
    } finally {
      if (mounted) setState(() => _sendingLoc = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ENREGISTREMENT VOCAL
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _startRec() async {
    if (_recActive || _recPreview) return;
    if (!await _rec.hasPermission()) {
      _showErr('Permission microphone refusée');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final p = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
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
          setState(() => _recDuration = Duration(seconds: _recDuration.inSeconds + 1));
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
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_recActive || !mounted) return;
      setState(() {
        for (int i = 0; i < _waveformBars.length - 1; i++) {
          _waveformBars[i] = _waveformBars[i + 1];
        }
        _currentAmplitude = 0.1 + _rand.nextDouble() * 0.85;
        final prev = _waveformBars[_waveformBars.length - 2];
        _waveformBars[_waveformBars.length - 1] = (prev * 0.3 + _currentAmplitude * 0.7).clamp(0.05, 1.0);
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
    _previewPlayer = AudioPlayer();
    await _previewPlayer!.setFilePath(p);
    _previewDur   = _previewPlayer!.duration ?? Duration.zero;
    _previewPos   = Duration.zero;
    _previewPlaying = false;
    _previewPosSub = _previewPlayer!.positionStream.listen((pos) {
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

  Future<void> _playAudio(String id, String url) async {
    try {
      for (final e in _players.entries) {
        if (e.key != id && e.value.playing) await e.value.stop();
      }
      _players[id] ??= AudioPlayer()
        ..playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed && mounted) setState(() {});
        });
      final p = _players[id]!;
      if (p.playing) {
        await p.pause();
      } else {
        await p.setUrl(url);
        await p.play();
      }
      if (mounted) setState(() {});
    } catch (_) { _showErr("Impossible de lire l'audio"); }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Future<void> _initVideo(String id, String url) async {
    if (_vCtrl.containsKey(id)) return;
    try {
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vc.initialize();
      final cc = ChewieController(
          videoPlayerController: vc,
          autoPlay: false,
          looping: false,
          aspectRatio: vc.value.aspectRatio,
          errorBuilder: (_, __) =>
              const Center(child: Icon(Icons.error, color: Colors.red)));
      if (mounted) setState(() { _vCtrl[id] = vc; _cCtrl[id] = cc; });
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: _buildAppBar(),
      body: Column(children: [
        if (widget.serviceName != null) _serviceBanner(),
        // Barre de recherche inline
        if (_isSearching) _buildSearchBar(),
        Expanded(child: _buildMsgList()),
        _buildOtherIndicator(),
        _buildInputBar(),
        if (_showEmojiPicker) _buildEmojiPicker(),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  APP BAR — SANS icônes d'appel/vidéo
  // ══════════════════════════════════════════════════════════════════════
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
      final isOnline   = pv.getUserOnlineStatus(widget.otherUser.id) || widget.otherUser.isOnline;
      final lastSeen   = pv.getUserLastSeen(widget.otherUser.id) ?? widget.otherUser.lastSeen;
      final isTyping   = pv.isUserTyping(widget.conversationId, widget.otherUser.id);
      final isRecording = pv.isUserRecording(widget.conversationId, widget.otherUser.id);
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
                        fontSize: 16, fontWeight: FontWeight.bold,
                        color: AppConstants.primaryRed))
                : null,
          ),
          if (isOnline) Positioned(
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            if (isRecording)
              Row(children: [
                AnimatedBuilder(animation: _pulseAnim,
                  builder: (_, __) => Icon(Icons.mic, size: 11,
                      color: Colors.white70.withOpacity(_pulseAnim.value))),
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
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        )),
      ]);
    }),
    // SEULEMENT recherche et menu (PAS d'icônes appel/vidéo)
    actions: [
      IconButton(
        icon: Icon(_isSearching ? Icons.close : Icons.search),
        onPressed: () {
          setState(() {
            if (_isSearching) {
              _isSearching = false;
              _searchCtrl.clear();
              _searchQuery = '';
              _searchResults = [];
              _searchCurrentIndex = -1;
            } else {
              _isSearching = true;
            }
          });
        },
      ),
      IconButton(icon: const Icon(Icons.more_vert), onPressed: _showOptions),
    ],
  );

  // ── Barre de recherche inline ───────────────────────────────────────
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher dans la conversation...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppConstants.primaryRed),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
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
            icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 20),
            onPressed: () => _navigateSearchResult(false),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
            onPressed: () => _navigateSearchResult(true),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ]),
    );
  }

  String _fmtSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'vu à l\'instant';
    if (diff.inMinutes < 60) return 'vu il y a ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'vu il y a ${diff.inHours} h';
    return 'vu le ${DateFormat('dd/MM/yy').format(d)}';
  }

  // ══════════════════════════════════════════════════════════════════════
  //  LISTE DE MESSAGES
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildMsgList() {
    return Consumer<MessageProvider>(
      builder: (ctx, pv, _) {
        final msgs = pv.getMessages(widget.conversationId);
        if (msgs.length > _lastMsgCount) {
          _lastMsgCount = msgs.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollBottom(animated: true);
            _markRead();
            NotificationService().cancelNotification(widget.conversationId);
          });
        }
        if (pv.isLoading && msgs.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryRed));
        }
        if (msgs.isEmpty) return _buildEmpty();
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final showDate = i == 0 || msgs[i].createdAt.day != msgs[i - 1].createdAt.day;
            // Vérifier si ce message correspond à la recherche
            final isHighlighted = _isSearching &&
                _searchResults.isNotEmpty &&
                _searchResults.contains(i) &&
                _searchQuery.isNotEmpty &&
                msgs[i].content.toLowerCase().contains(_searchQuery);
            final isCurrentSearch = _isSearching &&
                _searchCurrentIndex >= 0 &&
                _searchCurrentIndex < _searchResults.length &&
                _searchResults[_searchCurrentIndex] == i;

            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (showDate) _buildDateSep(msgs[i].createdAt),
              _buildSwipeable(msgs[i], i, isHighlighted, isCurrentSearch),
            ]);
          },
        );
      },
    );
  }

  Widget _buildDateSep(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    String label = diff == 0 ? "Aujourd'hui" : diff == 1 ? 'Hier'
        : DateFormat('dd MMMM yyyy', 'fr_FR').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3)],
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF3B3B3B), fontWeight: FontWeight.w500)),
      )),
    );
  }

  // ── Swipe pour répondre ─────────────────────────────────────────────
  Widget _buildSwipeable(MessageModel m, int index, bool isHighlighted, bool isCurrentSearch) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe vers la droite → répondre
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          HapticFeedback.mediumImpact();
          setState(() => _replyTo = m);
          _focus.requestFocus();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isCurrentSearch
            ? BoxDecoration(
                color: Colors.yellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              )
            : isHighlighted
                ? BoxDecoration(
                    color: Colors.yellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
        child: _buildBubble(m),
      ),
    );
  }

  Widget _buildBubble(MessageModel m) {
    final isMe  = m.isMe;
    final isErr = m.status == 'error';
    final bg = isErr ? Colors.red[50]!
        : isMe ? const Color(0xFFDCF8C6) : Colors.white;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 3, left: isMe ? 55 : 0, right: isMe ? 0 : 55),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.grey[300],
                backgroundImage: widget.otherUser.photoUrl != null
                    ? NetworkImage(widget.otherUser.photoUrl!) : null,
                child: widget.otherUser.photoUrl == null
                    ? Text(
                        widget.otherUser.name.isNotEmpty
                            ? widget.otherUser.name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 10, color: AppConstants.primaryRed))
                    : null),
            ),
            Flexible(
              child: GestureDetector(
                onLongPress: () => _msgMenu(m),
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: isMe ? const Radius.circular(14) : const Radius.circular(3),
                      bottomRight: isMe ? const Radius.circular(3) : const Radius.circular(14),
                    ),
                    border: isErr ? Border.all(color: Colors.red) : null,
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 3, offset: const Offset(0, 1))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Aperçu du message auquel on répond
                        if (m.replyTo != null) _buildReplyPreview(m.replyTo!),
                        _buildMsgContent(m),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(DateFormat('HH:mm').format(m.createdAt),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isMe ? const Color(0xFF6E8B6E) : Colors.grey[500])),
                            if (isMe) ...[const SizedBox(width: 3), _statusIcon(m)],
                          ]),
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

  // ── Aperçu du message cité ──────────────────────────────────────────
  Widget _buildReplyPreview(ReplyToModel reply) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: AppConstants.primaryRed, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(reply.senderName,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: AppConstants.primaryRed)),
        const SizedBox(height: 2),
        Text(
          reply.type == 'text' ? reply.content : '📎 ${_typeLabel(reply.type)}',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ]),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'image': return 'Image';
      case 'video': return 'Vidéo';
      case 'audio': case 'vocal': return 'Message vocal';
      case 'document': return 'Document';
      case 'location': return 'Localisation';
      default: return 'Message';
    }
  }

  Widget _statusIcon(MessageModel m) {
    if (m.status == 'sending')
      return const SizedBox(width: 12, height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF6E8B6E)));
    if (m.status == 'error')
      return const Icon(Icons.error_outline, size: 13, color: Colors.red);
    if (m.readAt != null)
      return const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB));
    return const Icon(Icons.done, size: 14, color: Color(0xFF6E8B6E));
  }

  Widget _buildMsgContent(MessageModel m) {
    switch (m.type) {
      case 'image':    return _buildImgContent(m);
      case 'video':    return _buildVidContent(m);
      case 'location': return _buildLocContent(m);
      case 'audio':
      case 'vocal':    return _buildAudioContent(m);
      case 'document': return _buildDocContent(m);
      default:
        if (m.content.isEmpty) return const SizedBox.shrink();
        return Text(m.content,
            style: const TextStyle(
                fontSize: 14.5, color: Color(0xFF2D2D2D), height: 1.35));
    }
  }

  Widget _buildImgContent(MessageModel m) {
    if (m.fileUrl == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _openImg(m.fileUrl!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(m.fileUrl!,
            width: 220, height: 180, fit: BoxFit.cover,
            loadingBuilder: (_, c, p) => p == null ? c
                : Container(width: 220, height: 180, color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorBuilder: (_, __, ___) => Container(
                width: 220, height: 180, color: Colors.grey[200],
                child: const Icon(Icons.broken_image))),
      ),
    );
  }

  Widget _buildVidContent(MessageModel m) {
    if (m.fileUrl == null) return const SizedBox.shrink();
    if (!_cCtrl.containsKey(m.id)) {
      _initVideo(m.id, m.fileUrl!);
      return Container(
          width: 220, height: 160,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          child: const Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    return SizedBox(width: 220, height: 160,
        child: ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Chewie(controller: _cCtrl[m.id]!)));
  }

  Widget _buildLocContent(MessageModel m) {
    final hasCoords = m.latitude != null && m.longitude != null;
    return GestureDetector(
      onTap: () => hasCoords ? _openLoc(m.latitude!, m.longitude!) : null,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (hasCoords)
              Stack(children: [
                SizedBox(
                  height: 130, width: double.infinity,
                  child: Image.network(
                    'https://staticmap.openstreetmap.de/staticmap.php?center=${m.latitude},${m.longitude}&zoom=15&size=400x200&markers=${m.latitude},${m.longitude},red',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 130, color: const Color(0xFFE8F4F0),
                      child: Center(child: Icon(Icons.map_outlined, size: 40, color: Colors.teal[300])),
                    ),
                  ),
                ),
                Positioned(bottom: 0, left: 0, right: 0,
                  child: Container(height: 40,
                    decoration: BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.35)])))),
                const Positioned.fill(child: Center(child: _MapPin())),
                Positioned(bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)]),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.directions, size: 12, color: Colors.blue[700]),
                      const SizedBox(width: 3),
                      Text('Itinéraire', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue[700])),
                    ]),
                  )),
              ])
            else
              Container(height: 80, color: const Color(0xFFE8F4F0),
                  child: Center(child: Icon(Icons.map_outlined, size: 36, color: Colors.teal[300]))),

            Container(
              color: m.isMe ? const Color(0xFFDCF8C6) : Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: AppConstants.primaryRed.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.location_on, size: 16, color: AppConstants.primaryRed)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Position partagée', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[700])),
                  if (m.content.isNotEmpty)
                    Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.3)),
                ])),
                Icon(Icons.open_in_new, size: 14, color: Colors.grey[400]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildAudioContent(MessageModel m) {
    final p = _players[m.id];
    final playing = p?.playing ?? false;
    return StreamBuilder<Duration>(
      stream: p?.positionStream ?? const Stream.empty(),
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = p?.duration ?? Duration.zero;
        final pct = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        return SizedBox(
          width: 210,
          child: Row(children: [
            GestureDetector(
              onTap: () { if (m.fileUrl != null) _playAudio(m.id, m.fileUrl!); },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: m.isMe ? const Color(0xFF25D366) : AppConstants.primaryRed,
                    shape: BoxShape.circle),
                child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
              SliderTheme(
                data: SliderThemeData(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    trackHeight: 3,
                    thumbColor: m.isMe ? const Color(0xFF25D366) : AppConstants.primaryRed,
                    activeTrackColor: m.isMe ? const Color(0xFF25D366) : AppConstants.primaryRed,
                    inactiveTrackColor: Colors.grey[300],
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10)),
                child: Slider(
                    value: pct.toDouble(),
                    onChanged: (v) => p?.seek(
                        Duration(milliseconds: (v * dur.inMilliseconds).toInt())))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(pos), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text(_fmt(dur), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ])),
            ])),
          ]),
        );
      },
    );
  }

  Widget _buildDocContent(MessageModel m) {
    if (m.fileUrl == null) return const SizedBox.shrink();
    final fn  = m.fileUrl!.split('/').last;
    final ext = fn.split('.').last.toLowerCase();
    final ico = ext == 'pdf' ? Icons.picture_as_pdf
        : (ext == 'doc' || ext == 'docx') ? Icons.description
        : Icons.insert_drive_file;
    return GestureDetector(
      onTap: () => _openUrl(m.fileUrl!),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!)),
        child: Row(children: [
          Icon(ico, color: AppConstants.primaryRed, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text(fn, style: const TextStyle(fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.download, size: 18, color: Colors.grey),
        ])),
    );
  }

  Widget _buildOtherIndicator() {
    return Consumer<MessageProvider>(builder: (_, pv, __) {
      final typing   = pv.isUserTyping(widget.conversationId, widget.otherUser.id);
      final recording = pv.isUserRecording(widget.conversationId, widget.otherUser.id);
      if (!typing && !recording) return const SizedBox.shrink();
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          if (recording) ...[
            AnimatedBuilder(animation: _pulseAnim, builder: (_, __) => Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(_pulseAnim.value),
                    shape: BoxShape.circle))),
            const SizedBox(width: 8),
            Text('${widget.otherUser.name} enregistre un vocal…',
                style: const TextStyle(fontSize: 12, color: Colors.red, fontStyle: FontStyle.italic)),
          ] else ...[
            _typingDots(),
            const SizedBox(width: 8),
            Text('${widget.otherUser.name} écrit…',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
          ],
        ]),
      );
    });
  }

  Widget _typingDots() {
    return AnimatedBuilder(animation: _pulseAnim, builder: (_, __) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t = (_pulseAnim.value + i * 0.33) % 1.0;
        return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 6, height: 6,
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3 + 0.7 * t),
                shape: BoxShape.circle));
      }),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BARRE D'INPUT
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildInputBar() => Container(
    color: const Color(0xFFF0F2F5),
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_recPreview) _buildPreviewBar(),
      if (_recActive && _recLocked) _buildLockedRecBar(),

      // Bannière de réponse
      if (_replyTo != null && !_isEditing) _buildReplyBanner(),

      // Bannière de modification
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

  // ── Bannière répondre à ─────────────────────────────────────────────
  Widget _buildReplyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: AppConstants.primaryRed, width: 3)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Répondre à ${_replyTo!.isMe ? "vous-même" : widget.otherUser.name}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppConstants.primaryRed)),
          const SizedBox(height: 2),
          Text(
            _replyTo!.type == 'text' ? _replyTo!.content : '📎 ${_typeLabel(_replyTo!.type)}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ])),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _replyTo = null),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  // ── Bannière modifier ───────────────────────────────────────────────
  Widget _buildEditBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.blue, width: 3)),
      ),
      child: Row(children: [
        const Icon(Icons.edit, size: 16, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Modifier le message',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
          Text(_editingMessage!.content, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ])),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: Colors.blue),
          onPressed: _cancelEdit,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _buildTextField() => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3, offset: const Offset(0, 1))]),
    child: Row(children: [
      const SizedBox(width: 14),
      Expanded(child: TextField(
        controller: _msgCtrl,
        focusNode: _focus,
        minLines: 1, maxLines: 5,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        enabled: !_sending && !_recActive && !_recPreview,
        style: const TextStyle(fontSize: 15, color: Color(0xFF2D2D2D)),
        decoration: InputDecoration(
            hintText: _isEditing ? 'Modifier le message...' : 'Message',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10)),
      )),
      // BOUTON EMOJI FONCTIONNEL
      IconButton(
          icon: Icon(
            _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
            color: _showEmojiPicker ? AppConstants.primaryRed : Colors.grey[500],
            size: 22,
          ),
          onPressed: () {
            setState(() => _showEmojiPicker = !_showEmojiPicker);
            if (_showEmojiPicker) {
              _focus.unfocus();
            } else {
              _focus.requestFocus();
            }
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
      const SizedBox(width: 4),
    ]),
  );

  // ── EMOJI PICKER ────────────────────────────────────────────────────
  Widget _buildEmojiPicker() {
    return Container(
      height: 200,
      color: Colors.white,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(children: [
            const Text('Emojis fréquents', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _showEmojiPicker = false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _frequentEmojis.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () {
                final emoji = _frequentEmojis[i];
                final currentText = _msgCtrl.text;
                final selection = _msgCtrl.selection;
                final newText = currentText.substring(0, selection.start) +
                    emoji +
                    currentText.substring(selection.end);
                _msgCtrl.text = newText;
                _msgCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: selection.start + emoji.length),
                );
                setState(() => _hasText = true);
              },
              child: Center(
                child: Text(_frequentEmojis[i], style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildAttachBtn() => PopupMenuButton<String>(
    icon: Container(
        width: 44, height: 44,
        decoration: const BoxDecoration(
            color: AppConstants.primaryRed, shape: BoxShape.circle),
        child: const Icon(Icons.add, color: Colors.white, size: 24)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    onSelected: (v) {
      switch (v) {
        case 'camera':   _pickImg(ImageSource.camera); break;
        case 'gallery':  _pickImg(ImageSource.gallery); break;
        case 'video':    _pickVid(ImageSource.gallery); break;
        case 'document': _pickDoc(); break;
        case 'location': _sendLoc(); break;
      }
    },
    itemBuilder: (_) => [
      _mi('camera',   Icons.camera_alt,        const Color(0xFF1DA1F2), 'Photo'),
      _mi('gallery',  Icons.photo,             const Color(0xFF9B59B6), 'Galerie'),
      _mi('video',    Icons.videocam,          const Color(0xFFF39C12), 'Vidéo'),
      _mi('document', Icons.insert_drive_file, const Color(0xFFE74C3C), 'Document'),
      PopupMenuItem(
        value: 'location',
        enabled: !_sendingLoc,
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.location_on, color: const Color(0xFF2ECC71), size: 18)),
          const SizedBox(width: 12),
          Text(_sendingLoc ? 'Envoi…' : 'Localisation',
              style: const TextStyle(fontSize: 14)),
        ])),
    ],
  );

  PopupMenuItem<String> _mi(String val, IconData icon, Color c, String label) =>
      PopupMenuItem(value: val, child: Row(children: [
        Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: c, size: 18)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 14)),
      ]));

  Widget _buildSendOrMic() {
    if (_hasText || _sending || _isEditing) {
      return GestureDetector(
        onTap: _sending ? null : () => _send(content: _msgCtrl.text),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48, height: 48,
          decoration: BoxDecoration(
              color: _sending ? Colors.grey : AppConstants.primaryRed,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: AppConstants.primaryRed.withOpacity(0.4),
                  blurRadius: 6, offset: const Offset(0, 2))]),
          child: _sending
              ? const Padding(padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Icon(_isEditing ? Icons.check : Icons.send, color: Colors.white, size: 22)),
      );
    }
    return _buildMicButton();
  }

  Widget _buildMicButton() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (_showSwipeHint && !_recActive)
          Positioned(
            bottom: 56,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder: (_, v, child) => Opacity(opacity: v,
                child: Transform.translate(offset: Offset(0, -8 * v), child: child)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 14),
                  SizedBox(width: 3),
                  Text('Maintenir & glisser', style: TextStyle(color: Colors.white, fontSize: 10)),
                ]),
              ),
            ),
          ),
        GestureDetector(
          key: _micKey,
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
              setState(() { _recLocked = true; _micDragX = 0; _micDragY = 0; });
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
            builder: (_, __) => Transform.scale(
              scale: _micScaleAnim.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _recActive ? 56 : 48,
                height: _recActive ? 56 : 48,
                decoration: BoxDecoration(
                    color: _recActive
                        ? (_micDragX < _kCancelX ? Colors.red : const Color(0xFF25D366))
                        : AppConstants.primaryRed,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: (_recActive ? const Color(0xFF25D366) : AppConstants.primaryRed).withOpacity(0.45),
                        blurRadius: _recActive ? 16 : 6,
                        spreadRadius: _recActive ? 3 : 0,
                        offset: const Offset(0, 2))]),
                child: _recActive
                    ? (_micDragX < _kCancelX
                        ? const Icon(Icons.delete_outline, color: Colors.white, size: 24)
                        : AnimatedBuilder(animation: _pulseAnim, builder: (_, __) =>
                            Icon(Icons.mic,
                                color: Colors.white.withOpacity(0.6 + 0.4 * _pulseAnim.value),
                                size: 24)))
                    : const Icon(Icons.mic, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
        if (_recActive && !_recLocked && _micDragY < -10)
          Positioned(
            bottom: 60,
            child: Opacity(
              opacity: ((-_micDragY - 10) / 60).clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)]),
                child: Icon(Icons.lock_outline, size: 16,
                    color: _micDragY < _kLockY ? Colors.green : Colors.grey[600]),
              ),
            ),
          ),
        if (_recActive && !_recLocked && _micDragX < -10)
          Positioned(
            right: 58,
            child: Opacity(
              opacity: ((-_micDragX - 10) / 60).clamp(0.0, 1.0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chevron_left, color: _micDragX < _kCancelX ? Colors.red : Colors.grey[600], size: 20),
                Text('Annuler', style: TextStyle(fontSize: 11,
                    color: _micDragX < _kCancelX ? Colors.red : Colors.grey[600])),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveRecBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 6)]),
      child: Row(children: [
        Row(children: [
          AnimatedBuilder(animation: _pulseAnim, builder: (_, __) => Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.5 + 0.5 * _pulseAnim.value),
                  shape: BoxShape.circle))),
          const SizedBox(width: 6),
          Text(_fmt(_recDuration),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: Color(0xFF2D2D2D), fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(width: 12),
        Expanded(child: _buildWaveform()),
        const SizedBox(width: 8),
        GestureDetector(onTap: _cancelRec,
            child: Icon(Icons.close, color: Colors.grey[500], size: 20)),
      ]),
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 32,
      child: AnimatedBuilder(
        animation: _waveCtrl,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _waveformBars.reversed.take(28).toList().reversed.map((amp) {
            final h = (4 + amp * 26).clamp(4.0, 30.0);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  height: h,
                  decoration: BoxDecoration(
                    color: amp > 0.5 ? const Color(0xFF25D366) : const Color(0xFF25D366).withOpacity(0.4 + amp * 0.6),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 6)]),
      child: Row(children: [
        AnimatedBuilder(animation: _pulseAnim, builder: (_, __) => Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.5 + 0.5 * _pulseAnim.value),
                shape: BoxShape.circle))),
        const SizedBox(width: 8),
        Text(_fmt(_recDuration),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
        const SizedBox(width: 8),
        Expanded(child: _buildWaveform()),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: _cancelRec,
            child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.delete_outline, color: Colors.red[600], size: 18))),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: _stopForPreview,
            child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 18))),
      ]),
    );
  }

  Widget _buildPreviewBar() {
    final pct = _previewDur.inMilliseconds > 0
        ? (_previewPos.inMilliseconds / _previewDur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppConstants.primaryRed.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)]),
      child: Row(children: [
        GestureDetector(
            onTap: _cancelPreview,
            child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, color: Colors.red, size: 18))),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: _togglePreview,
            child: Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
                child: Icon(_previewPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 24))),
        const SizedBox(width: 10),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
          SliderTheme(
            data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
                thumbColor: AppConstants.primaryRed,
                activeTrackColor: AppConstants.primaryRed,
                inactiveTrackColor: Colors.grey[300]),
            child: Slider(
                value: pct.toDouble(),
                onChanged: (v) => _previewPlayer?.seek(
                    Duration(milliseconds: (v * _previewDur.inMilliseconds).toInt())))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_fmt(_previewPos), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              Text(_fmt(_previewDur), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            ])),
        ])),
        const SizedBox(width: 10),
        GestureDetector(
            onTap: _sendPreview,
            child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 22))),
      ]),
    );
  }

  // ── Menu contextuel (long press) ────────────────────────────────────
  void _msgMenu(MessageModel m) => showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
        // Répondre
        ListTile(
            leading: const Icon(Icons.reply, color: AppConstants.primaryRed),
            title: const Text('Répondre'),
            onTap: () {
              Navigator.pop(context);
              setState(() { _replyTo = m; _isEditing = false; });
              _focus.requestFocus();
            }),
        // Copier
        ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copier'),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: m.content));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copié'), duration: Duration(seconds: 1)));
            }),
        // Modifier (seulement si c'est mon message, texte, et < 15 min)
        if (_canEdit(m))
          ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.blue),
              title: const Text('Modifier'),
              subtitle: const Text('Disponible pendant 15 min', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _startEdit(m);
              }),
        // Supprimer (seulement mes messages)
        if (m.isMe)
          ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Supprimer', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(m);
              }),
      ])));

  // ── Options (3 points) ──────────────────────────────────────────────
  void _showOptions() => showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        ListTile(
            leading: const Icon(Icons.search, color: AppConstants.primaryRed),
            title: const Text('Rechercher dans la conversation'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _isSearching = true);
            }),
        ListTile(
            leading: const Icon(Icons.clear_all),
            title: const Text('Effacer la conversation'),
            onTap: () {
              Navigator.pop(context);
              _showErr('Bientôt disponible');
            }),
      ]));

  // ── Helpers ────────────────────────────────────────────────────────────

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7), shape: BoxShape.circle),
          child: Icon(Icons.chat_bubble_outline, size: 52, color: Colors.grey[400])),
      const SizedBox(height: 16),
      Text('Aucun message',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.grey[600])),
      const SizedBox(height: 6),
      Text('Envoyez votre premier message',
          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
    ]),
  );

  Widget _serviceBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    color: Colors.orange[50],
    child: Row(children: [
      Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
      const SizedBox(width: 8),
      Expanded(child: Text('À propos de : ${widget.serviceName}',
          style: TextStyle(fontSize: 12, color: Colors.orange[700]))),
    ]),
  );

  void _openImg(String url) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(child: InteractiveViewer(child: Image.network(url))))));

  Future<void> _openLoc(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2)));
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _recTimer?.cancel();
    _waveformTimer?.cancel();
    _pulseCtrl.dispose();
    _micScaleCtrl.dispose();
    _waveCtrl.dispose();
    _searchCtrl.dispose();

    _msgProvider?.setActiveConversation(null);
    MessagePollingService().removeMessageListener(widget.conversationId, _onPollingMessages);

    if (_recActive) {
      _rec.stop().catchError((_) {}).then((p) {
        if (p != null) try { File(p).deleteSync(); } catch (_) {}
      });
    }
    _rec.dispose();
    _disposePreview();
    for (final p in _players.values) p.dispose();
    for (final c in _vCtrl.values)  c.dispose();
    for (final c in _cCtrl.values)  c.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    if (_typingActive) {
      _msgProvider?.sendTypingIndicator(widget.conversationId, false);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Widget PIN de carte
// ══════════════════════════════════════════════════════════════════════
class _MapPin extends StatefulWidget {
  const _MapPin();

  @override
  State<_MapPin> createState() => _MapPinState();
}

class _MapPinState extends State<_MapPin> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0.0, end: -6.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _bounce.value),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: AppConstants.primaryRed,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: AppConstants.primaryRed.withOpacity(0.5),
                    blurRadius: 8, spreadRadius: 2)]),
            child: const Icon(Icons.location_on, color: Colors.white, size: 18),
          ),
          Container(
            width: 8, height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ]),
      ),
    );
  }
}