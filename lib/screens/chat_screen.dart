// lib/screens/chat_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VERSION FINALE — Réception temps réel fiable + UI mic WhatsApp
//
// CORRECTIONS CRITIQUES :
// 1. Réception temps réel : Consumer<MessageProvider> wraps le ListView
//    directement. On compare msgs.length > _lastMsgCount DANS le builder
//    pour scroller → pas de addListener qui conflit.
// 2. Bouton mic style WhatsApp : LongPress démarre, glisse GAUCHE annule,
//    glisse HAUT verrouille. Pas de conflit scroll vertical.
// 3. dispose() sécurisé : pas de context.read sur provider disposed.
// 4. Fond couleur WhatsApp, bulles vertes/blanches cohérentes.
// ═══════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:async';
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
import '../providers/message_provider.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';

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
  final ScrollController       _scroll = ScrollController();
  final FocusNode              _focus  = FocusNode();
  final ImagePicker            _picker = ImagePicker();
  final AudioRecorder          _rec    = AudioRecorder();
  final Map<String, AudioPlayer>           _players = {};
  final Map<String, VideoPlayerController> _vCtrl   = {};
  final Map<String, ChewieController>      _cCtrl   = {};

  bool   _sending     = false;
  bool   _hasText     = false;
  bool   _sendingLoc  = false;
  bool   _typingActive = false;
  Timer? _typingTimer;

  // Compteur messages — pour détecter de nouveaux messages dans Consumer
  int _lastMsgCount = 0;

  // Animations
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _micScaleCtrl;
  late Animation<double>   _micScaleAnim;

  // ── État enregistrement vocal ──────────────────────────────────────
  bool     _recActive   = false;
  bool     _recLocked   = false;
  bool     _recPreview  = false;
  String?  _recPath;
  Duration _recDuration = Duration.zero;
  Timer?   _recTimer;
  Offset?  _micTouchStart;
  double   _micDragX = 0.0;
  double   _micDragY = 0.0;

  static const double _kCancelX = -80.0;
  static const double _kLockY   = -80.0;

  // Lecteur aperçu
  AudioPlayer? _previewPlayer;
  bool         _previewPlaying = false;
  Duration     _previewPos     = Duration.zero;
  Duration     _previewDur     = Duration.zero;
  StreamSubscription? _previewPosSub;
  StreamSubscription? _previewStateSub;

  // Référence sécurisée au provider
  MessageProvider? _msgProvider;

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
    _micScaleAnim = Tween<double>(begin: 1.0, end: 1.25)
        .animate(CurvedAnimation(parent: _micScaleCtrl, curve: Curves.elasticOut));

    _msgCtrl.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _msgProvider = context.read<MessageProvider>();
      _loadMessages();
      _msgProvider!.fetchOnlineStatus(widget.otherUser.id);
      NotificationService().cancelNotification(widget.conversationId);
      NotificationService().onNotificationTap = (data) {
        final convId = data['conversation_id']?.toString() ?? '';
        if (convId != widget.conversationId && mounted) Navigator.pop(context);
      };
    });
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

  // ── Envoi ──────────────────────────────────────────────────────────
  Future<void> _send({
    String? content, String? filePath, String? type,
    double? lat, double? lng,
  }) async {
    final text = content?.trim() ?? '';
    if (text.isEmpty && filePath == null && lat == null) return;
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final t = type ?? (filePath != null ? _fileType(filePath) : 'text');
      await _msgProvider?.sendMessage(
        widget.conversationId,
        type:      lat != null ? 'location' : t,
        content:   text.isEmpty ? null : text,
        filePath:  filePath,
        latitude:  lat,
        longitude: lng,
      );
      if (type == null || type == 'text') {
        _msgCtrl.clear();
        setState(() => _hasText = false);
      }
      _scrollBottom();
    } catch (_) { _showErr("Impossible d'envoyer"); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  String _fileType(String p) {
    final e = p.split('.').last.toLowerCase();
    if (['jpg','jpeg','png','gif','webp'].contains(e)) return 'image';
    if (['mp4','mov','avi','mkv','3gp'].contains(e))  return 'video';
    if (['mp3','m4a','aac','wav','ogg'].contains(e))  return 'audio';
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
            if (p.street?.isNotEmpty == true)   p.street!,
            if (p.locality?.isNotEmpty == true)  p.locality!,
            if (p.country?.isNotEmpty == true)   p.country!,
          ];
          if (pts.isNotEmpty) addr = pts.join(', ');
        }
      } catch (_) {}
      await _send(content: addr, type: 'location',
          lat: pos.latitude, lng: pos.longitude);
    } catch (_) { _showErr('Erreur localisation'); }
    finally { if (mounted) setState(() => _sendingLoc = false); }
  }

  // ── Enregistrement vocal ───────────────────────────────────────────
  void _onMicLongPressStart(LongPressStartDetails d) {
    _micTouchStart = d.globalPosition;
    _micDragX = 0; _micDragY = 0;
    _startRec();
  }

  void _onMicLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (_micTouchStart == null || !_recActive) return;
    setState(() {
      _micDragX = d.globalPosition.dx - _micTouchStart!.dx;
      _micDragY = d.globalPosition.dy - _micTouchStart!.dy;
    });
  }

  void _onMicLongPressEnd(LongPressEndDetails d) {
    if (!_recActive) { _micTouchStart = null; return; }
    if (_micDragY < _kLockY) {
      setState(() { _recLocked = true; _micDragX = 0; _micDragY = 0; });
    } else if (_micDragX < _kCancelX) {
      _cancelRec();
    } else {
      _stopForPreview();
    }
    _micTouchStart = null;
  }

  Future<void> _startRec() async {
    if (_recActive || _recPreview) return;
    if (!await _rec.hasPermission()) {
      _showErr('Permission microphone refusée'); return;
    }
    try {
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      _micScaleCtrl.forward();
      setState(() { _recActive = true; _recLocked = false; _recDuration = Duration.zero; });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recActive && mounted) {
          setState(() => _recDuration = Duration(seconds: _recDuration.inSeconds + 1));
        }
      });
      _msgProvider?.sendRecordingIndicator(widget.conversationId, true);
    } catch (_) { _showErr("Impossible de démarrer l'enregistrement"); }
  }

  Future<void> _stopForPreview() async {
    if (!_recActive) return;
    _recTimer?.cancel();
    _micScaleCtrl.reverse();
    _msgProvider?.sendRecordingIndicator(widget.conversationId, false);
    final dur = _recDuration;
    try {
      final path = await _rec.stop();
      if (!mounted) return;
      if (path != null && dur.inSeconds >= 1) {
        await _initPreview(path);
        setState(() { _recActive = false; _recLocked = false; _recPreview = true;
          _recPath = path; _micDragX = 0; _micDragY = 0; });
      } else {
        if (path != null) try { File(path).deleteSync(); } catch (_) {}
        setState(() { _recActive = false; _recLocked = false; _recDuration = Duration.zero; });
        if (dur.inSeconds < 1) _showErr('Trop court (min. 1 s)');
      }
    } catch (_) {
      if (mounted) setState(() { _recActive = false; _recLocked = false; });
    }
  }

  Future<void> _cancelRec() async {
    _recTimer?.cancel();
    _micScaleCtrl.reverse();
    _msgProvider?.sendRecordingIndicator(widget.conversationId, false);
    try {
      final p = await _rec.stop();
      if (p != null) try { File(p).deleteSync(); } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() { _recActive = false; _recLocked = false;
      _recDuration = Duration.zero; _micDragX = 0; _micDragY = 0; });
  }

  void _cancelPreview() {
    _disposePreview();
    if (_recPath != null) try { File(_recPath!).deleteSync(); } catch (_) {}
    setState(() { _recPreview = false; _recPath = null; });
  }

  Future<void> _sendPreview() async {
    if (_recPath == null) return;
    final path = _recPath!;
    _disposePreview();
    setState(() { _recPreview = false; _recPath = null; });
    await _send(filePath: path, type: 'audio');
  }

  Future<void> _initPreview(String path) async {
    await _previewPlayer?.dispose();
    _previewPlayer = AudioPlayer();
    await _previewPlayer!.setFilePath(path);
    _previewDur = _previewPlayer!.duration ?? Duration.zero;
    _previewPos = Duration.zero; _previewPlaying = false;
    _previewPosSub = _previewPlayer!.positionStream.listen((p) {
      if (mounted) setState(() => _previewPos = p);
    });
    _previewStateSub = _previewPlayer!.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() => _previewPlaying = false);
      }
    });
  }

  void _disposePreview() {
    _previewPosSub?.cancel(); _previewStateSub?.cancel();
    _previewPlayer?.stop(); _previewPlayer?.dispose(); _previewPlayer = null;
    _previewPlaying = false; _previewPos = Duration.zero; _previewDur = Duration.zero;
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
      if (p.playing) { await p.pause(); } else { await p.setUrl(url); await p.play(); }
      if (mounted) setState(() {});
    } catch (_) { _showErr("Impossible de lire l'audio"); }
  }

  String _fmt(Duration d) {
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  Future<void> _initVideo(String id, String url) async {
    if (_vCtrl.containsKey(id)) return;
    try {
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vc.initialize();
      final cc = ChewieController(videoPlayerController: vc, autoPlay: false, looping: false,
        aspectRatio: vc.value.aspectRatio,
        errorBuilder: (_, __) => const Center(child: Icon(Icons.error, color: Colors.red)));
      if (mounted) setState(() { _vCtrl[id] = vc; _cCtrl[id] = cc; });
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: _buildAppBar(),
      body: Column(children: [
        if (widget.serviceName != null) _serviceBanner(),
        Expanded(child: _buildMsgList()),
        _buildOtherIndicator(),
        _buildInputBar(),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppConstants.primaryRed,
    foregroundColor: Colors.white,
    elevation: 1,
    leadingWidth: 32,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context),
      padding: EdgeInsets.zero,
    ),
    titleSpacing: 0,
    title: Consumer<MessageProvider>(builder: (_, pv, __) {
      final isOnline   = pv.getUserOnlineStatus(widget.otherUser.id) || widget.otherUser.isOnline;
      final lastSeen   = pv.getUserLastSeen(widget.otherUser.id) ?? widget.otherUser.lastSeen;
      final isTyping   = pv.isUserTyping(widget.conversationId, widget.otherUser.id);
      final isRecording= pv.isUserRecording(widget.conversationId, widget.otherUser.id);
      return Row(children: [
        Stack(children: [
          CircleAvatar(
            radius: 20, backgroundColor: Colors.white,
            backgroundImage: widget.otherUser.photoUrl != null
                ? NetworkImage(widget.otherUser.photoUrl!) : null,
            child: widget.otherUser.photoUrl == null
                ? Text(widget.otherUser.name.isNotEmpty
                    ? widget.otherUser.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold, color: AppConstants.primaryRed))
                : null,
          ),
          if (isOnline) Positioned(bottom: 1, right: 1,
            child: Container(width: 10, height: 10,
              decoration: BoxDecoration(color: const Color(0xFF25D366),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)))),
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
    actions: [
      IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
      IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
      IconButton(icon: const Icon(Icons.more_vert), onPressed: _showOptions),
    ],
  );

  String _fmtSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'vu à l\'instant';
    if (diff.inMinutes < 60) return 'vu il y a ${diff.inMinutes} min';
    if (diff.inHours   < 24) return 'vu il y a ${diff.inHours} h';
    return 'vu le ${DateFormat('dd/MM/yy').format(d)}';
  }

  // ── Liste de messages ─────────────────────────────────────────────
  Widget _buildMsgList() {
    return Consumer<MessageProvider>(
      builder: (ctx, pv, _) {
        final msgs = pv.getMessages(widget.conversationId);

        // ⭐ CLEF DE VOUTE : détecter nouveaux messages ICI dans le Consumer
        if (msgs.length > _lastMsgCount) {
          _lastMsgCount = msgs.length;
          // Scroll après le frame courant
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
            final showDate = i == 0 ||
                msgs[i].createdAt.day != msgs[i - 1].createdAt.day;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (showDate) _buildDateSep(msgs[i].createdAt),
              _buildBubble(msgs[i]),
            ]);
          },
        );
      },
    );
  }

  Widget _buildDateSep(DateTime d) {
    final now = DateTime.now();
    String label;
    final diff = now.difference(d).inDays;
    if (diff == 0) label = "Aujourd'hui";
    else if (diff == 1) label = 'Hier';
    else label = DateFormat('dd MMMM yyyy', 'fr_FR').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
              blurRadius: 3)],
        ),
        child: Text(label, style: const TextStyle(
            fontSize: 12, color: Color(0xFF3B3B3B), fontWeight: FontWeight.w500)),
      )),
    );
  }

  Widget _buildBubble(MessageModel m) {
    final isMe  = m.isMe;
    final isErr = m.status == 'error';
    final bg    = isErr ? Colors.red[50]! : isMe
        ? const Color(0xFFDCF8C6) : Colors.white;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: 3, left: isMe ? 55 : 0, right: isMe ? 0 : 55),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe)
              Padding(padding: const EdgeInsets.only(right: 4, bottom: 2),
                child: CircleAvatar(radius: 14,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: widget.otherUser.photoUrl != null
                      ? NetworkImage(widget.otherUser.photoUrl!) : null,
                  child: widget.otherUser.photoUrl == null
                      ? Text(widget.otherUser.name.isNotEmpty
                          ? widget.otherUser.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 10,
                              color: AppConstants.primaryRed)) : null)),
            Flexible(
              child: GestureDetector(
                onLongPress: () => _msgMenu(m),
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(14),
                      topRight:    const Radius.circular(14),
                      bottomLeft:  isMe ? const Radius.circular(14) : const Radius.circular(3),
                      bottomRight: isMe ? const Radius.circular(3)  : const Radius.circular(14)),
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
                        _buildMsgContent(m),
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(DateFormat('HH:mm').format(m.createdAt),
                                style: TextStyle(fontSize: 10,
                                    color: isMe ? const Color(0xFF6E8B6E)
                                        : Colors.grey[500])),
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

  Widget _statusIcon(MessageModel m) {
    if (m.status == 'sending') return const SizedBox(width: 12, height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF6E8B6E)));
    if (m.status == 'error')   return const Icon(Icons.error_outline, size: 13, color: Colors.red);
    if (m.readAt != null)      return const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB));
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
        return Text(m.content, style: const TextStyle(
            fontSize: 14.5, color: Color(0xFF2D2D2D), height: 1.35));
    }
  }

  Widget _buildImgContent(MessageModel m) {
    if (m.fileUrl == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _openImg(m.fileUrl!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(m.fileUrl!, width: 220, height: 180, fit: BoxFit.cover,
          loadingBuilder: (_, c, p) => p == null ? c : Container(width: 220, height: 180,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
          errorBuilder: (_, __, ___) => Container(width: 220, height: 180,
              color: Colors.grey[200], child: const Icon(Icons.broken_image))),
      ),
    );
  }

  Widget _buildVidContent(MessageModel m) {
    if (m.fileUrl == null) return const SizedBox.shrink();
    if (!_cCtrl.containsKey(m.id)) {
      _initVideo(m.id, m.fileUrl!);
      return Container(width: 220, height: 160,
          decoration: BoxDecoration(color: Colors.black,
              borderRadius: BorderRadius.circular(8)),
          child: const Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    return SizedBox(width: 220, height: 160,
        child: ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Chewie(controller: _cCtrl[m.id]!)));
  }

  Widget _buildLocContent(MessageModel m) {
    return GestureDetector(
      onTap: () => _openLoc(m.latitude ?? 0, m.longitude ?? 0),
      child: Container(width: 220,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (m.latitude != null && m.longitude != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: Image.network(
                'https://staticmap.openstreetmap.de/staticmap.php?'
                'center=${m.latitude},${m.longitude}&zoom=15&size=220x100'
                '&markers=${m.latitude},${m.longitude},red',
                width: 220, height: 100, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 220, height: 80,
                    color: Colors.grey[200], child: const Icon(Icons.map, color: Colors.grey))),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              const Icon(Icons.location_on, size: 16, color: AppConstants.primaryRed),
              const SizedBox(width: 6),
              Expanded(child: Text(
                m.content.isNotEmpty ? m.content : 'Localisation partagée',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildAudioContent(MessageModel m) {
    final p       = _players[m.id];
    final playing = p?.playing ?? false;
    return StreamBuilder<Duration>(
      stream: p?.positionStream ?? const Stream.empty(),
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = p?.duration ?? Duration.zero;
        final pct = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
        return SizedBox(width: 200, child: Row(children: [
          GestureDetector(
            onTap: () { if (m.fileUrl != null) _playAudio(m.id, m.fileUrl!); },
            child: Container(width: 38, height: 38,
              decoration: BoxDecoration(
                color: m.isMe ? const Color(0xFF25D366) : AppConstants.primaryRed,
                shape: BoxShape.circle),
              child: Icon(playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 22)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
            SliderTheme(data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              trackHeight: 3,
              thumbColor:         m.isMe ? const Color(0xFF25D366) : AppConstants.primaryRed,
              activeTrackColor:   m.isMe ? const Color(0xFF25D366) : AppConstants.primaryRed,
              inactiveTrackColor: Colors.grey[300],
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10)),
              child: Slider(value: pct,
                onChanged: (v) => p?.seek(
                    Duration(milliseconds: (v * dur.inMilliseconds).toInt())))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text(_fmt(dur), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ])),
          ])),
        ]));
      },
    );
  }

  Widget _buildDocContent(MessageModel m) {
    if (m.fileUrl == null) return const SizedBox.shrink();
    final fn = m.fileUrl!.split('/').last;
    final ext = fn.split('.').last.toLowerCase();
    final ico = ext == 'pdf' ? Icons.picture_as_pdf
        : (ext == 'doc' || ext == 'docx') ? Icons.description
        : Icons.insert_drive_file;
    return GestureDetector(
      onTap: () => _openUrl(m.fileUrl!),
      child: Container(width: 200, padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey[100],
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

  // ── Indicateur typing/recording ────────────────────────────────────
  Widget _buildOtherIndicator() {
    return Consumer<MessageProvider>(builder: (_, pv, __) {
      final typing    = pv.isUserTyping(widget.conversationId, widget.otherUser.id);
      final recording = pv.isUserRecording(widget.conversationId, widget.otherUser.id);
      if (!typing && !recording) return const SizedBox.shrink();
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          if (recording) ...[
            AnimatedBuilder(animation: _pulseAnim,
              builder: (_, __) => Container(width: 8, height: 8,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(_pulseAnim.value),
                  shape: BoxShape.circle))),
            const SizedBox(width: 8),
            Text('${widget.otherUser.name} enregistre un vocal…',
                style: const TextStyle(fontSize: 12, color: Colors.red,
                    fontStyle: FontStyle.italic)),
          ] else ...[
            _typingDots(),
            const SizedBox(width: 8),
            Text('${widget.otherUser.name} écrit…',
                style: TextStyle(fontSize: 12, color: Colors.grey[600],
                    fontStyle: FontStyle.italic)),
          ],
        ]),
      );
    });
  }

  Widget _typingDots() {
    return AnimatedBuilder(animation: _pulseAnim, builder: (_, __) =>
      Row(mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_pulseAnim.value + i * 0.33) % 1.0;
          return Container(margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3 + 0.7 * t),
              shape: BoxShape.circle));
        }),
      ));
  }

  // ── Barre de saisie ────────────────────────────────────────────────
  Widget _buildInputBar() => Container(
    color: const Color(0xFFF0F2F5),
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_recPreview) _buildPreviewBar(),
      if (_recActive && _recLocked && !_recPreview) _buildLockedBar(),
      if (!_recPreview) Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _buildAttachBtn(),
        const SizedBox(width: 4),
        Expanded(child: _buildTextField()),
        const SizedBox(width: 6),
        _buildSendOrMic(),
      ]),
      if (_recActive && !_recLocked && !_recPreview) _buildRecIndicator(),
    ]),
  );

  Widget _buildTextField() => Container(
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
          blurRadius: 3, offset: const Offset(0, 1))]),
    child: Row(children: [
      const SizedBox(width: 14),
      Expanded(child: TextField(
        controller: _msgCtrl, focusNode: _focus,
        minLines: 1, maxLines: 5,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        enabled: !_sending && !_recActive && !_recPreview,
        style: const TextStyle(fontSize: 15, color: Color(0xFF2D2D2D)),
        decoration: InputDecoration(
          hintText: 'Message',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10)),
      )),
      IconButton(icon: Icon(Icons.emoji_emotions_outlined,
          color: Colors.grey[500], size: 22),
        onPressed: () {}, padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
      const SizedBox(width: 4),
    ]),
  );

  Widget _buildAttachBtn() => PopupMenuButton<String>(
    icon: Container(width: 44, height: 44,
      decoration: const BoxDecoration(
          color: AppConstants.primaryRed, shape: BoxShape.circle),
      child: const Icon(Icons.add, color: Colors.white, size: 24)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    onSelected: (v) {
      switch (v) {
        case 'camera':   _pickImg(ImageSource.camera);  break;
        case 'gallery':  _pickImg(ImageSource.gallery); break;
        case 'video':    _pickVid(ImageSource.gallery); break;
        case 'document': _pickDoc();                   break;
        case 'location': _sendLoc();                   break;
      }
    },
    itemBuilder: (_) => [
      _mi('camera',   Icons.camera_alt,        const Color(0xFF1DA1F2), 'Photo'),
      _mi('gallery',  Icons.photo,             const Color(0xFF9B59B6), 'Galerie'),
      _mi('video',    Icons.videocam,          const Color(0xFFF39C12), 'Vidéo'),
      _mi('document', Icons.insert_drive_file, const Color(0xFFE74C3C), 'Document'),
      PopupMenuItem(value: 'location', enabled: !_sendingLoc,
        child: Row(children: [
          Container(padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: const Color(0xFF2ECC71).withOpacity(0.15),
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
        Container(padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: c, size: 18)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 14)),
      ]));

  // ── Bouton envoi / mic ─────────────────────────────────────────────
  Widget _buildSendOrMic() {
    if (_hasText || _sending) {
      return GestureDetector(
        onTap: _sending ? null : () => _send(content: _msgCtrl.text),
        child: AnimatedContainer(duration: const Duration(milliseconds: 150),
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _sending ? Colors.grey : AppConstants.primaryRed,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppConstants.primaryRed.withOpacity(0.4),
                blurRadius: 6, offset: const Offset(0, 2))]),
          child: _sending
              ? const Padding(padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send, color: Colors.white, size: 22)),
      );
    }
    // Bouton mic style WhatsApp
    return _buildMicBtn();
  }

  Widget _buildMicBtn() {
    final canceling = _recActive && _micDragX < _kCancelX;
    final locking   = _recActive && _micDragY < _kLockY;

    return Stack(clipBehavior: Clip.none, children: [
      // Indicateur gauche (annuler)
      if (_recActive && _micDragX < -20)
        Positioned(right: 56, top: 12,
          child: Opacity(opacity: ((-_micDragX - 20) / 60).clamp(0.0, 1.0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chevron_left, size: 18,
                  color: canceling ? Colors.red : Colors.grey[500]),
              Icon(Icons.chevron_left, size: 18,
                  color: canceling ? Colors.red : Colors.grey[400]),
              Text('Annuler',
                  style: TextStyle(fontSize: 11,
                      color: canceling ? Colors.red : Colors.grey[500])),
            ]))),
      // Indicateur haut (lock)
      if (_recActive && _micDragY < -20)
        Positioned(bottom: 56, right: 6,
          child: Opacity(opacity: ((-_micDragY - 20) / 60).clamp(0.0, 1.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 16,
                  color: locking ? Colors.green : Colors.grey[400]),
              Icon(Icons.keyboard_arrow_up, size: 20,
                  color: locking ? Colors.green : Colors.grey[400]),
            ]))),
      // Hint "Maintenir"
      if (!_recActive)
        Positioned(bottom: 52, right: -18,
          child: IgnorePointer(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('⬆ Maintenir',
                style: TextStyle(color: Colors.white, fontSize: 10))))),
      // Bouton
      GestureDetector(
        onLongPressStart:      _onMicLongPressStart,
        onLongPressMoveUpdate: _onMicLongPressMoveUpdate,
        onLongPressEnd:        _onMicLongPressEnd,
        onLongPressCancel:     () { if (_recActive) _cancelRec(); },
        child: AnimatedBuilder(animation: _micScaleAnim,
          builder: (_, __) => Transform.scale(scale: _micScaleAnim.value,
            child: AnimatedContainer(duration: const Duration(milliseconds: 150),
              width:  _recActive ? 54 : 48,
              height: _recActive ? 54 : 48,
              decoration: BoxDecoration(
                color: canceling ? Colors.red
                    : locking    ? Colors.green
                    : AppConstants.primaryRed,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: (canceling ? Colors.red
                      : locking   ? Colors.green
                      : AppConstants.primaryRed).withOpacity(0.45),
                  blurRadius: _recActive ? 14 : 6,
                  spreadRadius: _recActive ? 2 : 0,
                  offset: const Offset(0, 2))]),
              child: _recActive
                  ? AnimatedBuilder(animation: _pulseAnim, builder: (_, __) =>
                      Icon(
                        canceling ? Icons.delete_outline
                            : locking  ? Icons.lock_outline
                            : Icons.mic,
                        color: Colors.white.withOpacity(0.55 + 0.45 * _pulseAnim.value),
                        size: 24))
                  : const Icon(Icons.mic, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildRecIndicator() {
    final canceling = _micDragX < _kCancelX;
    final locking   = _micDragY < _kLockY;
    return AnimatedContainer(duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: canceling ? Colors.red[50] : locking ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: canceling
            ? Colors.red.withOpacity(0.4)
            : locking ? Colors.green.withOpacity(0.4)
            : Colors.grey[300]!)),
      child: Row(children: [
        AnimatedBuilder(animation: _pulseAnim, builder: (_, __) =>
          Container(width: 10, height: 10,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.4 + 0.6 * _pulseAnim.value),
              shape: BoxShape.circle))),
        const SizedBox(width: 10),
        Text(_fmt(_recDuration), style: TextStyle(fontSize: 15,
            fontWeight: FontWeight.w600,
            color: canceling ? Colors.red : const Color(0xFF2D2D2D))),
        const SizedBox(width: 12),
        Expanded(child: Text(
          canceling ? 'Relâchez pour annuler'
              : locking ? 'Relâchez pour verrouiller'
              : '← Annuler   ↑ Bloquer',
          style: TextStyle(fontSize: 11,
              color: canceling ? Colors.red
                  : locking ? Colors.green[700]
                  : Colors.grey[600]),
          overflow: TextOverflow.ellipsis)),
        GestureDetector(onTap: _cancelRec,
            child: const Icon(Icons.close, color: Colors.grey, size: 20)),
      ]),
    );
  }

  Widget _buildLockedBar() => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey[300]!)),
    child: Row(children: [
      AnimatedBuilder(animation: _pulseAnim, builder: (_, __) =>
        Container(width: 10, height: 10,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.4 + 0.6 * _pulseAnim.value),
            shape: BoxShape.circle))),
      const SizedBox(width: 10),
      Text(_fmt(_recDuration), style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
      const SizedBox(width: 8),
      Text('Verrouillé', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const Spacer(),
      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
          onPressed: _cancelRec, padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
      GestureDetector(
        onTap: _stopForPreview,
        child: Container(padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
          child: const Icon(Icons.send, color: Colors.white, size: 18))),
    ]),
  );

  Widget _buildPreviewBar() {
    final pct = _previewDur.inMilliseconds > 0
        ? (_previewPos.inMilliseconds / _previewDur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppConstants.primaryRed.withOpacity(0.3))),
      child: Row(children: [
        GestureDetector(onTap: _cancelPreview,
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 20))),
        const SizedBox(width: 8),
        GestureDetector(onTap: _togglePreview,
          child: Container(width: 40, height: 40,
            decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
            child: Icon(_previewPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white, size: 24))),
        const SizedBox(width: 10),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
          SliderTheme(data: SliderThemeData(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 3,
            thumbColor: AppConstants.primaryRed,
            activeTrackColor: AppConstants.primaryRed,
            inactiveTrackColor: Colors.grey[300]),
            child: Slider(value: pct,
              onChanged: (v) => _previewPlayer?.seek(
                  Duration(milliseconds: (v * _previewDur.inMilliseconds).toInt())))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_previewPos), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text(_fmt(_previewDur), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ])),
        ])),
        const SizedBox(width: 10),
        GestureDetector(onTap: _sendPreview,
          child: Container(width: 44, height: 44,
            decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
            child: const Icon(Icons.send, color: Colors.white, size: 22))),
      ]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  Widget _buildEmpty() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), shape: BoxShape.circle),
        child: Icon(Icons.chat_bubble_outline, size: 52, color: Colors.grey[400])),
      const SizedBox(height: 16),
      Text('Aucun message', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.bold, color: Colors.grey[600])),
      const SizedBox(height: 6),
      Text('Envoyez votre premier message',
          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
    ],
  ));

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
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _msgMenu(MessageModel m) => showModalBottomSheet(context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      Container(width: 36, height: 4, decoration: BoxDecoration(
          color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
      ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('Copier'),
        onTap: () {
          Navigator.pop(context);
          Clipboard.setData(ClipboardData(text: m.content));
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copié'), duration: Duration(seconds: 1)));
        }),
    ])));

  void _showOptions() => showModalBottomSheet(context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      ListTile(leading: const Icon(Icons.search, color: AppConstants.primaryRed),
        title: const Text('Rechercher'),
        onTap: () { Navigator.pop(context); _showErr('Bientôt disponible'); }),
    ]));

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2)));
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _recTimer?.cancel();
    _pulseCtrl.dispose();
    _micScaleCtrl.dispose();

    // Arrêter l'enregistrement si en cours
    if (_recActive) {
      _rec.stop().catchError((_) {}).then((p) {
        if (p != null) try { File(p).deleteSync(); } catch (_) {}
      });
    }
    _rec.dispose();

    _disposePreview();
    for (final p in _players.values) p.dispose();
    for (final c in _vCtrl.values)   c.dispose();
    for (final c in _cCtrl.values)   c.dispose();

    _msgCtrl.dispose();
    _scroll.dispose();
    _focus.dispose();

    // Envoyer typing=false si encore actif (sans context.read)
    if (_typingActive) {
      _msgProvider?.sendTypingIndicator(widget.conversationId, false);
    }

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}