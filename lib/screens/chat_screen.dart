// lib/screens/chat_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// CORRECTIONS DÉFINITIVES:
// 1. VOCAL: glisser le bouton micro VERS LE HAUT pour démarrer
//    (DragGesture vertical, pas longPress)
//    → Pendant le glisser: le micro s'ouvre, l'enregistrement commence
//    → On relâche en haut: enregistrement verrouillé (continu)
//    → On relâche en bas (< seuil): arrêt + aperçu
// 2. LOCATION: détection automatique via MessageModel (lat/lng présents)
// 3. STATUT: fetchOnlineStatus() appelé à l'ouverture du chat
// 4. HEURE: DateTime.now() = heure locale, pas UTC
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
    with WidgetsBindingObserver, TickerProviderStateMixin {

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController       _scroll = ScrollController();
  final FocusNode              _focus  = FocusNode();
  final ImagePicker            _picker = ImagePicker();
  final AudioRecorder          _rec    = AudioRecorder();
  final Map<String, AudioPlayer>           _players = {};
  final Map<String, VideoPlayerController> _vCtrl   = {};
  final Map<String, ChewieController>      _cCtrl   = {};

  bool   _typing      = false;
  Timer? _typingTmr;
  bool   _otherTyping = false;
  bool   _sending     = false;
  bool   _hasText     = false;
  bool   _sendingLoc  = false;

  // ── État enregistrement vocal ──────────────────────────────────────
  // Machine à états:
  //   idle → (glisser haut depuis bouton mic) → recording
  //   recording + glisser assez haut → locked (verrouillé, relâcher OK)
  //   recording + relâcher bas → stopPreview
  //   locked → (bouton stop) → stopPreview
  //   stopPreview → hasPreview (écoute + envoi)
  bool     _recording  = false;
  bool     _locked     = false;
  bool     _hasPreview = false;
  String?  _previewPath;
  Duration _recDur = Duration.zero;
  Timer?   _recTmr;

  // ── Lecteur aperçu ─────────────────────────────────────────────────
  AudioPlayer? _prePl;
  bool         _prePlaying = false;
  Duration     _prePos     = Duration.zero;
  Duration     _preDur     = Duration.zero;
  StreamSubscription? _prePosStream;
  StreamSubscription? _preStateStream;

  // ── Animation pulse ────────────────────────────────────────────────
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);

    _loadMsgs();
    _setupListeners();
    _markRead();

    // ⭐ Récupérer le statut en ligne dès l'ouverture du chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageProvider>().fetchOnlineStatus(widget.otherUser.id);
      NotificationService().onNotificationTap = (id) {
        if (id != widget.conversationId && mounted) Navigator.pop(context);
      };
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      context.read<MessageProvider>().loadMessages(widget.conversationId);
      context.read<MessageProvider>().fetchOnlineStatus(widget.otherUser.id);
      _markRead();
    }
  }

  void _loadMsgs() async {
    await context.read<MessageProvider>().loadMessages(widget.conversationId);
    _toBottom(animated: false);
  }

  void _markRead() =>
      context.read<MessageProvider>().markConversationAsRead(widget.conversationId);

  void _setupListeners() {
    _msgCtrl.addListener(() {
      final h = _msgCtrl.text.trim().isNotEmpty;
      if (h != _hasText) setState(() => _hasText = h);
      if (h && !_typing)      { _typing = true;  _sendTyping(true);  }
      else if (!h && _typing) { _typing = false; _sendTyping(false); }
      _typingTmr?.cancel();
      _typingTmr = Timer(const Duration(seconds: 2), () {
        if (_typing) { _typing = false; _sendTyping(false); }
      });
    });
    context.read<MessageProvider>().addListener(_checkTyping);
  }

  void _checkTyping() {
    if (!mounted) return;
    final t = context.read<MessageProvider>()
        .isUserTyping(widget.conversationId, widget.otherUser.id);
    if (_otherTyping != t) setState(() => _otherTyping = t);
  }

  Future<void> _sendTyping(bool v) =>
      context.read<MessageProvider>().sendTypingIndicator(widget.conversationId, v);

  void _toBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(max,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  // ── ENVOI ─────────────────────────────────────────────────────────────────────
  Future<void> _send({
    String? content, String? filePath, String? type,
    double? lat, double? lng,
  }) async {
    final text = content?.trim() ?? '';
    if (text.isEmpty && filePath == null && (lat == null || lng == null)) return;
    if (_sending) return;
    setState(() => _sending = true);
    try {
      String t = type ?? (filePath != null ? _fileType(filePath) : 'text');
      if (lat != null && lng != null) t = 'location';
      await context.read<MessageProvider>().sendMessage(
        widget.conversationId, type: t,
        content:  text.isEmpty ? null : text,
        filePath: filePath, latitude: lat, longitude: lng,
      );
      _msgCtrl.clear();
      setState(() => _hasText = false);
      _toBottom();
    } catch (_) { _err("Impossible d'envoyer le message"); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  String _fileType(String p) {
    final e = p.split('.').last.toLowerCase();
    if (['jpg','jpeg','png','gif','bmp','webp'].contains(e)) return 'image';
    if (['mp4','mov','avi','mkv','3gp','webm'].contains(e)) return 'video';
    if (['mp3','m4a','aac','wav','ogg'].contains(e))        return 'audio';
    return 'document';
  }

  // ── MÉDIAS ────────────────────────────────────────────────────────────────────
  Future<void> _photo()    async { try { final i = await _picker.pickImage(source:ImageSource.camera,  maxWidth:1024,imageQuality:80); if(i!=null) await _send(filePath:i.path,type:'image'); } catch(_){_err('Erreur photo');} }
  Future<void> _gallery()  async { try { final i = await _picker.pickImage(source:ImageSource.gallery, maxWidth:1024,imageQuality:80); if(i!=null) await _send(filePath:i.path,type:'image'); } catch(_){_err('Erreur image');} }
  Future<void> _videoGal() async { try { final v = await _picker.pickVideo(source:ImageSource.gallery, maxDuration:const Duration(minutes:5)); if(v!=null) await _send(filePath:v.path,type:'video'); } catch(_){_err('Erreur vidéo');} }
  Future<void> _videoCam() async { try { final v = await _picker.pickVideo(source:ImageSource.camera,  maxDuration:const Duration(minutes:2)); if(v!=null) await _send(filePath:v.path,type:'video'); } catch(_){_err('Erreur vidéo');} }
  Future<void> _document() async { try { final r = await FilePicker.platform.pickFiles(type:FileType.any,allowMultiple:false); if(r?.files.single.path!=null) await _send(filePath:r!.files.single.path!,type:'document'); } catch(_){_err('Erreur document');} }

  // ── LOCALISATION ──────────────────────────────────────────────────────────────
  Future<void> _sendLoc() async {
    if (_sendingLoc) return;
    setState(() => _sendingLoc = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _err('Permission localisation refusée'); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String address = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final pts = <String>[];
          if (p.street   != null && p.street!.isNotEmpty)   pts.add(p.street!);
          if (p.locality != null && p.locality!.isNotEmpty) pts.add(p.locality!);
          if (p.country  != null && p.country!.isNotEmpty)  pts.add(p.country!);
          if (pts.isNotEmpty) address = pts.join(', ');
        }
      } catch (_) {}
      // content = adresse, type = location, lat/lng obligatoires
      await _send(content: address, type: 'location', lat: pos.latitude, lng: pos.longitude);
    } catch (e) { _err('Erreur localisation'); }
    finally { if (mounted) setState(() => _sendingLoc = false); }
  }

  // ════════════════════════════════════════════════════════════════════
  //  ENREGISTREMENT VOCAL — GLISSER VERS LE HAUT
  //
  //  Comportement exact demandé:
  //  1. L'utilisateur TIRE l'icône micro VERS LE HAUT
  //  2. Dès qu'il dépasse le seuil (60px vers le haut) → enregistrement démarre
  //  3. En relâchant:
  //     - Si déplacé > 120px vers le haut → enregistrement verrouillé
  //     - Sinon → arrêt + aperçu
  //  4. En mode verrouillé: bouton stop → aperçu, corbeille → annuler
  //  5. Mode aperçu: écouter → envoyer ou annuler
  // ════════════════════════════════════════════════════════════════════

  // Seuil de déclenchement de l'enregistrement (px vers le haut)
  static const double _kStartThreshold = 60.0;
  // Seuil de verrouillage (px vers le haut)
  static const double _kLockThreshold  = 120.0;

  // Position Y initiale du doigt au moment où il touche le bouton
  double? _dragStartY;
  // Déplacement vertical actuel (négatif = vers le haut)
  double  _dragDeltaY = 0.0;
  // Enregistrement démarré par le drag
  bool    _recStartedByDrag = false;

  // ─── Drag démarre (doigt pose sur le bouton) ──────────────────────
  void _onMicDragStart(DragStartDetails d) {
    _dragStartY        = d.globalPosition.dy;
    _dragDeltaY        = 0.0;
    _recStartedByDrag  = false;
  }

  // ─── Drag en cours ────────────────────────────────────────────────
  void _onMicDragUpdate(DragUpdateDetails d) {
    if (_dragStartY == null) return;
    _dragDeltaY = d.globalPosition.dy - _dragStartY!; // négatif = vers le haut

    // Démarrer l'enregistrement dès que le seuil est atteint
    if (_dragDeltaY < -_kStartThreshold && !_recStartedByDrag && !_recording) {
      _recStartedByDrag = true;
      _startRec();
    }

    // Mettre à jour l'UI (verrouillage visuel)
    if (_recording && mounted) setState(() {});
  }

  // ─── Doigt relâché ────────────────────────────────────────────────
  void _onMicDragEnd(DragEndDetails d) {
    if (!_recording) { _dragStartY = null; return; }

    if (_dragDeltaY < -_kLockThreshold) {
      // Déplacé assez haut → verrouiller l'enregistrement
      setState(() => _locked = true);
    } else {
      // Relâché avant le seuil de lock → arrêter + aperçu
      _stopPreview();
    }
    _dragStartY = null;
  }

  // ─── Doigt relâché annulairement (geste interrompu) ──────────────
  void _onMicDragCancel() {
    if (_recording) _cancelRec();
    _dragStartY = null;
  }

  // ── Démarrer l'enregistrement ─────────────────────────────────────
  Future<void> _startRec() async {
    if (_recording || _hasPreview) return;
    final hasPerm = await _rec.hasPermission();
    if (!hasPerm) { _err('Permission microphone refusée'); return; }
    try {
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      if (mounted) setState(() { _recording = true; _locked = false; _recDur = Duration.zero; });
      _recTmr = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recording && mounted) setState(() => _recDur = Duration(seconds: _recDur.inSeconds + 1));
      });
    } catch (e) { _err("Impossible de démarrer l'enregistrement"); }
  }

  // ── Arrêt + mode aperçu ───────────────────────────────────────────
  Future<void> _stopPreview() async {
    if (!_recording) return;
    _recTmr?.cancel();
    final capturedDur = _recDur; // capturer AVANT reset
    try {
      final path = await _rec.stop();
      if (!mounted) return;
      if (path != null && capturedDur.inSeconds >= 1) {
        await _initPre(path);
        setState(() {
          _recording    = false;
          _locked       = false;
          _hasPreview   = true;
          _previewPath  = path;
          _dragDeltaY   = 0;
        });
      } else {
        if (path != null) try { File(path).deleteSync(); } catch (_) {}
        setState(() { _recording = false; _locked = false; _recDur = Duration.zero; });
        if (capturedDur.inSeconds < 1) _err('Enregistrement trop court (min. 1s)');
      }
    } catch (e) {
      if (mounted) setState(() { _recording = false; _locked = false; });
    }
  }

  // ── Annuler l'enregistrement ──────────────────────────────────────
  Future<void> _cancelRec() async {
    _recTmr?.cancel();
    try { final p = await _rec.stop(); if (p != null) try { File(p).deleteSync(); } catch (_) {} } catch (_) {}
    if (mounted) setState(() { _recording = false; _locked = false; _recDur = Duration.zero; _dragDeltaY = 0; });
  }

  // ── Annuler l'aperçu ──────────────────────────────────────────────
  void _cancelPreview() {
    _prePosStream?.cancel(); _preStateStream?.cancel();
    _prePl?.stop(); _prePl?.dispose(); _prePl = null;
    if (_previewPath != null) try { File(_previewPath!).deleteSync(); } catch (_) {}
    setState(() { _hasPreview = false; _previewPath = null; _prePlaying = false; _prePos = Duration.zero; _preDur = Duration.zero; });
  }

  // ── Envoyer depuis l'aperçu ───────────────────────────────────────
  Future<void> _sendPreview() async {
    if (_previewPath == null) return;
    final path = _previewPath!;
    _prePosStream?.cancel(); _preStateStream?.cancel();
    _prePl?.stop(); _prePl?.dispose(); _prePl = null;
    setState(() { _hasPreview = false; _previewPath = null; _prePlaying = false; _prePos = Duration.zero; _preDur = Duration.zero; });
    await _send(filePath: path, type: 'audio');
  }

  // ── Init lecteur aperçu ───────────────────────────────────────────
  Future<void> _initPre(String path) async {
    await _prePl?.dispose();
    _prePl = AudioPlayer();
    await _prePl!.setFilePath(path);
    _preDur = _prePl!.duration ?? Duration.zero;
    _prePosStream   = _prePl!.positionStream.listen((p) { if (mounted) setState(() => _prePos = p); });
    _preStateStream = _prePl!.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) setState(() => _prePlaying = false);
    });
  }

  Future<void> _togglePre() async {
    if (_prePl == null) return;
    if (_prePlaying) { await _prePl!.pause(); setState(() => _prePlaying = false); }
    else {
      if (_prePl!.processingState == ProcessingState.completed) await _prePl!.seek(Duration.zero);
      await _prePl!.play(); setState(() => _prePlaying = true);
    }
  }

  // ── Lecture audio (messages) ──────────────────────────────────────
  Future<void> _playAudio(String id, String url) async {
    try {
      for (final e in _players.entries) { if (e.key != id && e.value.playing) await e.value.stop(); }
      AudioPlayer? p = _players[id];
      if (p == null) {
        p = AudioPlayer(); _players[id] = p;
        p.playerStateStream.listen((s) { if (s.processingState == ProcessingState.completed && mounted) setState(() {}); });
      }
      if (p.playing) { await p.pause(); } else { await p.setUrl(url); await p.play(); }
      if (mounted) setState(() {});
    } catch (_) { _err("Impossible de lire l'audio"); }
  }

  String _fmt(Duration d) {
    f(int n) => n.toString().padLeft(2, '0');
    return '${f(d.inMinutes.remainder(60))}:${f(d.inSeconds.remainder(60))}';
  }

  Future<void> _initVideo(String id, String url) async {
    if (_vCtrl.containsKey(id)) return;
    try {
      final vc = VideoPlayerController.networkUrl(Uri.parse(url)); await vc.initialize();
      final cc = ChewieController(videoPlayerController: vc, autoPlay: false, looping: false,
        aspectRatio: vc.value.aspectRatio, placeholder: Container(color: Colors.black),
        errorBuilder: (_, __) => const Center(child: Icon(Icons.error, color: Colors.red)));
      if (mounted) setState(() { _vCtrl[id] = vc; _cCtrl[id] = cc; });
    } catch (e) { debugPrint('Video: $e'); }
  }

  // ══════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: _appBarTitle(),
        actions: [
          IconButton(icon: const Icon(Icons.phone), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _options),
        ],
      ),
      body: Column(children: [
        if (widget.serviceName != null) _svcBanner(),
        Expanded(child: Consumer<MessageProvider>(builder: (ctx, pv, _) {
          final msgs = pv.getMessages(widget.conversationId);
          if (pv.isLoading && msgs.isEmpty)
            return const Center(child: CircularProgressIndicator(color: AppConstants.primaryRed));
          if (msgs.isEmpty) return _empty();
          WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(animated: false));
          return _msgList(msgs);
        })),
        _inputBar(),
      ]),
    );
  }

  Widget _appBarTitle() => Consumer<MessageProvider>(builder: (ctx, pv, _) {
    final isOnline = pv.getUserOnlineStatus(widget.otherUser.id) || widget.otherUser.isOnline;
    final lastSeen = pv.getUserLastSeen(widget.otherUser.id) ?? widget.otherUser.lastSeen;

    return Row(children: [
      Stack(children: [
        CircleAvatar(
          radius: 18, backgroundColor: Colors.white,
          backgroundImage: widget.otherUser.photoUrl != null
              ? NetworkImage(widget.otherUser.photoUrl!) : null,
          child: widget.otherUser.photoUrl == null
              ? Text(widget.otherUser.name.isNotEmpty ? widget.otherUser.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppConstants.primaryRed))
              : null,
        ),
        if (isOnline) Positioned(bottom: 0, right: 0,
          child: Container(width: 10, height: 10,
            decoration: BoxDecoration(
              color: Colors.green, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2)))),
      ]),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.otherUser.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        if (_otherTyping)
          const Text('En train d\'écrire…',
              style: TextStyle(fontSize: 11, color: Colors.white70))
        else if (isOnline)
          const Text('En ligne',
              style: TextStyle(fontSize: 11, color: Colors.white70))
        else if (lastSeen != null)
          Text('Vu ${_fmtSeen(lastSeen)}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ])),
    ]);
  });

  String _fmtSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours   < 24) return 'il y a ${diff.inHours} h';
    return DateFormat('dd/MM/yy HH:mm').format(d);
  }

  // ── LISTE DE MESSAGES ─────────────────────────────────────────────────────────
  Widget _msgList(List<MessageModel> msgs) => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    itemCount: msgs.length,
    itemBuilder: (ctx, i) {
      final m = msgs[i];
      final showDate = i == 0 || msgs[i].createdAt.day != msgs[i-1].createdAt.day;
      return Column(children: [if (showDate) _dateSep(m.createdAt), _bubble(m)]);
    },
  );

  Widget _dateSep(DateTime d) {
    final now = DateTime.now();
    String lbl;
    if (now.difference(d).inDays == 0) lbl = "Aujourd'hui";
    else if (now.difference(d).inDays == 1) lbl = 'Hier';
    else lbl = DateFormat('dd MMMM yyyy', 'fr_FR').format(d);
    return Container(margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12)),
        child: Text(lbl, style: TextStyle(fontSize: 11, color: Colors.grey[700])))));
  }

  Widget _bubble(MessageModel m) {
    final isMe = m.isMe; final isErr = m.status == 'error';
    return Padding(padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) Padding(padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: CircleAvatar(radius: 14, backgroundColor: Colors.grey[200],
              backgroundImage: widget.otherUser.photoUrl != null
                  ? NetworkImage(widget.otherUser.photoUrl!) : null,
              child: widget.otherUser.photoUrl == null
                  ? Text(widget.otherUser.name.isNotEmpty ? widget.otherUser.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 10, color: AppConstants.primaryRed)) : null)),
          Flexible(child: GestureDetector(
            onLongPress: () => _msgMenu(m),
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isErr ? Colors.red[50] : isMe ? AppConstants.primaryRed : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4)  : const Radius.circular(16)),
                border:     isErr ? Border.all(color: Colors.red) : null,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (m.type != 'text') _media(m),
                if (m.content.isNotEmpty && m.type != 'location' && m.type != 'audio' && m.type != 'vocal')
                  Padding(padding: EdgeInsets.only(top: m.type != 'text' ? 6 : 0),
                    child: Text(m.content, style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87, fontSize: 14))),
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  // ⭐ Heure en heure locale GMT+1 (déjà en local grâce au model)
                  Text(DateFormat('HH:mm').format(m.createdAt),
                      style: TextStyle(
                          color: isErr ? Colors.red : isMe ? Colors.white60 : Colors.grey[500],
                          fontSize: 10)),
                  if (isMe) ...[const SizedBox(width: 3), _status(m)],
                ]),
              ]),
            ),
          )),
          if (isMe) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _status(MessageModel m) {
    if (m.status == 'sending') return const SizedBox(width: 10, height: 10,
        child: CircularProgressIndicator(color: Colors.white60, strokeWidth: 1.5));
    if (m.status == 'error') return const Icon(Icons.error_outline, color: Colors.red, size: 12);
    return Icon(m.readAt != null ? Icons.done_all : Icons.done, size: 12,
        color: m.readAt != null ? Colors.lightBlue[200] : Colors.white60);
  }

  void _msgMenu(MessageModel m) => showModalBottomSheet(context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 8),
      ListTile(leading: const Icon(Icons.copy), title: const Text('Copier'), onTap: () {
        Navigator.pop(context);
        Clipboard.setData(ClipboardData(text: m.content));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copié'), duration: Duration(seconds: 1)));
      }),
    ])));

  // ── MÉDIAS ────────────────────────────────────────────────────────────────────
  Widget _media(MessageModel m) {
    switch (m.type) {
      case 'image':
        if (m.fileUrl == null) return const SizedBox.shrink();
        return GestureDetector(onTap: () => _fullImg(m.fileUrl!),
          child: ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Image.network(m.fileUrl!, height: 200, width: double.infinity, fit: BoxFit.cover,
              loadingBuilder: (_, c, p) => p == null ? c : Container(height: 200, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
              errorBuilder: (_, __, ___) => Container(height: 200, color: Colors.grey[300], child: const Center(child: Icon(Icons.broken_image, size: 40))))));

      case 'video':
        if (m.fileUrl == null) return const SizedBox.shrink();
        if (!_cCtrl.containsKey(m.id)) { _initVideo(m.id, m.fileUrl!); return Container(height: 180, color: Colors.black, child: const Center(child: CircularProgressIndicator())); }
        return SizedBox(height: 180, child: Chewie(controller: _cCtrl[m.id]!));

      // ⭐ LOCALISATION — détectée automatiquement dans MessageModel.fromJson
      case 'location':
        return GestureDetector(
          onTap: () => _openLoc(m.latitude ?? 0, m.longitude ?? 0),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: m.isMe ? const Color(0xFFB71C1C) : Colors.blue[50],
              borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.location_on, color: m.isMe ? Colors.white : Colors.blue[700], size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  m.content.isNotEmpty ? m.content : 'Localisation partagée',
                  style: TextStyle(color: m.isMe ? Colors.white : Colors.blue[800],
                      fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
              if (m.latitude != null && m.longitude != null) ...[
                const SizedBox(height: 8),
                // Miniature de carte
                ClipRRect(borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    'https://staticmap.openstreetmap.de/staticmap.php?'
                    'center=${m.latitude},${m.longitude}&zoom=15&size=260x110'
                    '&markers=${m.latitude},${m.longitude},red',
                    height: 100, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(height: 50, color: Colors.grey[200],
                        child: Icon(Icons.map, color: Colors.grey[400], size: 28)),
                  )),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.open_in_new, size: 11, color: m.isMe ? Colors.white70 : Colors.blue[600]),
                  const SizedBox(width: 4),
                  Text('Ouvrir dans Google Maps',
                      style: TextStyle(fontSize: 11, color: m.isMe ? Colors.white70 : Colors.blue[600])),
                ]),
              ],
            ]),
          ),
        );

      case 'audio': case 'vocal': return _audioBubble(m);

      case 'document':
        if (m.fileUrl == null) return const SizedBox.shrink();
        return GestureDetector(onTap: () => _openFile(m.fileUrl!),
          child: Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: m.isMe ? const Color(0xFFB71C1C) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(_fileIco(m.fileUrl!), color: m.isMe ? Colors.white : Colors.grey[700]),
              const SizedBox(width: 8),
              Expanded(child: Text(m.fileUrl!.split('/').last,
                  style: TextStyle(color: m.isMe ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.w500, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              Icon(Icons.download, size: 18, color: m.isMe ? Colors.white : Colors.grey[600]),
            ])));

      default: return const SizedBox.shrink();
    }
  }

  Widget _audioBubble(MessageModel m) {
    final p = _players[m.id]; final playing = p?.playing ?? false;
    return StreamBuilder<Duration>(
      stream: p?.positionStream ?? const Stream.empty(),
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = p?.duration ?? Duration.zero;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: m.isMe ? const Color(0xFFB71C1C) : Colors.grey[100],
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(onTap: () { if (m.fileUrl != null) _playAudio(m.id, m.fileUrl!); },
              child: Container(width: 34, height: 34,
                decoration: BoxDecoration(
                    color: m.isMe ? Colors.white24 : Colors.grey[300], shape: BoxShape.circle),
                child: Icon(playing ? Icons.pause : Icons.play_arrow,
                    color: m.isMe ? Colors.white : AppConstants.primaryRed, size: 20))),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SliderTheme(data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                trackHeight: 2,
                thumbColor:         m.isMe ? Colors.white : AppConstants.primaryRed,
                activeTrackColor:   m.isMe ? Colors.white : AppConstants.primaryRed,
                inactiveTrackColor: m.isMe ? Colors.white38 : Colors.grey[300]),
                child: Slider(
                  value: dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0,
                  onChanged: (v) => p?.seek(Duration(milliseconds: (v * dur.inMilliseconds).toInt())))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(pos), style: TextStyle(fontSize: 9, color: m.isMe ? Colors.white70 : Colors.grey[600])),
                  Text(_fmt(dur), style: TextStyle(fontSize: 9, color: m.isMe ? Colors.white70 : Colors.grey[600])),
                ])),
            ])),
          ]),
        );
      });
  }

  // ── BARRE DE SAISIE ───────────────────────────────────────────────────────────
  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
    decoration: BoxDecoration(color: Colors.white, boxShadow: [
      BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, -3))]),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Mode aperçu audio
      if (_hasPreview) _previewBar(),
      // Mode enregistrement verrouillé
      if (_recording && _locked && !_hasPreview) _lockedBar(),
      // Mode normal
      if (!_hasPreview) Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _attachBtn(),
        Expanded(child: _textField()),
        const SizedBox(width: 6),
        _sendOrMicArea(),
      ]),
      // Indicateur enregistrement non-verrouillé
      if (_recording && !_locked && !_hasPreview) _recIndicator(),
    ]),
  );

  Widget _textField() => Container(
    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(22)),
    child: TextField(
      controller: _msgCtrl, focusNode: _focus,
      decoration: InputDecoration(hintText: 'Votre message…',
        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      maxLines: null, keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      enabled: !_sending && !_recording && !_hasPreview,
    ),
  );

  // ── ZONE ENVOI / MIC ──────────────────────────────────────────────────────────
  Widget _sendOrMicArea() {
    // Bouton envoi texte
    if (_hasText || _sending) {
      return GestureDetector(
        onTap: _sending ? null : () => _send(content: _msgCtrl.text),
        child: Container(width: 44, height: 44,
          decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
          child: _sending
              ? const Padding(padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send, color: Colors.white, size: 22)));
    }

    // Enregistrement verrouillé → bouton stop vert
    if (_recording && _locked) {
      return GestureDetector(
        onTap: _stopPreview,
        child: Container(width: 44, height: 44,
          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
          child: const Icon(Icons.stop, color: Colors.white, size: 22)));
    }

    // ⭐ BOUTON MICRO — glisser vers le haut pour enregistrer
    // GestureDetector vertical drag pour détecter le glisser
    final isActive   = _recording || (_dragStartY != null && _dragDeltaY < -10);
    final isLocking  = _dragDeltaY < -_kLockThreshold;
    final progress   = _dragStartY != null
        ? ((-_dragDeltaY - _kStartThreshold) / (_kLockThreshold - _kStartThreshold)).clamp(0.0, 1.0)
        : 0.0;

    return Stack(clipBehavior: Clip.none, children: [
      // Indicateur de progression (arc) quand on glisse
      if (_dragStartY != null && _dragDeltaY < -_kStartThreshold)
        Positioned(
          bottom: 50, left: -8,
          child: Container(
            width: 60, height: 60,
            child: CircularProgressIndicator(
              value: progress, strokeWidth: 3,
              color: isLocking ? Colors.green : AppConstants.primaryRed,
              backgroundColor: Colors.grey[200],
            ),
          ),
        ),
      // Hint "Glisser ↑" quand on ne glisse pas
      if (!_recording && _dragStartY == null)
        Positioned(
          bottom: 48,
          left: -30,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: const Text('↑ Glisser', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        ),
      // LE BOUTON
      GestureDetector(
        onVerticalDragStart:  _onMicDragStart,
        onVerticalDragUpdate: _onMicDragUpdate,
        onVerticalDragEnd:    _onMicDragEnd,
        onVerticalDragCancel: _onMicDragCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width:  isActive ? 52 : 44,
          height: isActive ? 52 : 44,
          decoration: BoxDecoration(
            color: isActive
                ? (isLocking ? Colors.green : Colors.red[700])
                : AppConstants.primaryRed,
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 16, spreadRadius: 4)]
                : [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)],
          ),
          child: isActive
              ? AnimatedBuilder(animation: _pulse, builder: (_, __) =>
                  Icon(
                    isLocking ? Icons.lock : Icons.mic,
                    color: Colors.white.withOpacity(0.6 + 0.4 * _pulse.value),
                    size: 24))
              : const Icon(Icons.mic, color: Colors.white, size: 22),
        ),
      ),
    ]);
  }

  // Indicateur enregistrement non-verrouillé
  Widget _recIndicator() => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.5 + 0.5 * _pulse.value), shape: BoxShape.circle))),
      const SizedBox(width: 10),
      Text(_fmt(_recDur), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red)),
      const SizedBox(width: 10),
      Text('Relâchez pour aperçu, montez pour verrouiller',
          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      const Spacer(),
      GestureDetector(onTap: _cancelRec,
          child: Icon(Icons.delete_outline, color: Colors.grey[500], size: 22)),
    ]),
  );

  // Barre enregistrement verrouillé
  Widget _lockedBar() => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.5 + 0.5 * _pulse.value), shape: BoxShape.circle))),
      const SizedBox(width: 8),
      Text(_fmt(_recDur), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red)),
      const SizedBox(width: 8),
      Text('Enregistrement…', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      const Spacer(),
      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _cancelRec),
      IconButton(icon: const Icon(Icons.stop_circle, color: AppConstants.primaryRed, size: 32), onPressed: _stopPreview),
    ]),
  );

  // Barre aperçu audio avant envoi
  Widget _previewBar() => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
        color: Colors.grey[100], borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppConstants.primaryRed.withOpacity(0.3))),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
        onPressed: _cancelPreview, padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
      GestureDetector(onTap: _togglePre,
        child: Container(width: 38, height: 38,
          decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
          child: Icon(_prePlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22))),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SliderTheme(data: SliderThemeData(
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 3,
          thumbColor: AppConstants.primaryRed, activeTrackColor: AppConstants.primaryRed,
          inactiveTrackColor: Colors.grey[300]),
          child: Slider(
            value: _preDur.inMilliseconds > 0
                ? (_prePos.inMilliseconds / _preDur.inMilliseconds).clamp(0.0, 1.0) : 0.0,
            onChanged: (v) => _prePl?.seek(Duration(milliseconds: (v * _preDur.inMilliseconds).toInt())))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_fmt(_prePos), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            Text(_fmt(_preDur), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ])),
      ])),
      const SizedBox(width: 8),
      GestureDetector(onTap: _sendPreview,
        child: Container(width: 42, height: 42,
          decoration: const BoxDecoration(color: AppConstants.primaryRed, shape: BoxShape.circle),
          child: const Icon(Icons.send, color: Colors.white, size: 22))),
    ]),
  );

  Widget _attachBtn() => PopupMenuButton<String>(
    icon: Icon(Icons.attach_file, color: AppConstants.primaryRed, size: 22),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: (v) {
      switch (v) {
        case 'camera':   _photo();    break;
        case 'image':    _gallery();  break;
        case 'video':    _videoGal(); break;
        case 'rec_vid':  _videoCam(); break;
        case 'doc':      _document(); break;
        case 'location': _sendLoc();  break;
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'camera',   child: _MI(Icons.camera_alt,        Colors.blue,   'Prendre une photo')),
      const PopupMenuItem(value: 'image',    child: _MI(Icons.image,             Colors.green,  'Choisir une image')),
      const PopupMenuItem(value: 'video',    child: _MI(Icons.video_library,     Colors.purple, 'Choisir une vidéo')),
      const PopupMenuItem(value: 'rec_vid',  child: _MI(Icons.videocam,          Colors.red,    'Enregistrer une vidéo')),
      const PopupMenuItem(value: 'doc',      child: _MI(Icons.insert_drive_file, Colors.orange, 'Document')),
      PopupMenuItem(value: 'location', enabled: !_sendingLoc,
        child: _MI(Icons.location_on, Colors.red, _sendingLoc ? 'Envoi…' : 'Ma localisation')),
    ],
  );

  Widget _svcBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), color: Colors.orange[50],
    child: Row(children: [
      Icon(Icons.info_outline, size: 15, color: Colors.orange[700]), const SizedBox(width: 8),
      Expanded(child: Text('À propos de: ${widget.serviceName}',
          style: TextStyle(fontSize: 12, color: Colors.orange[700]))),
    ]));

  Widget _empty() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]), const SizedBox(height: 14),
    Text('Aucun message', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.grey[500])),
    const SizedBox(height: 6),
    Text('Envoyez votre premier message', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
  ]));

  void _fullImg(String url) => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
    body: Center(child: InteractiveViewer(child: Image.network(url))))));

  Future<void> _openLoc(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    else _err("Impossible d'ouvrir la localisation");
  }

  Future<void> _openFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    else _err("Impossible d'ouvrir le fichier");
  }

  IconData _fileIco(String url) {
    final e = url.split('.').last.toLowerCase();
    if (e == 'pdf') return Icons.picture_as_pdf;
    if (e == 'doc' || e == 'docx') return Icons.description;
    if (e == 'xls' || e == 'xlsx') return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _options() => showModalBottomSheet(context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Container(padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.search, color: AppConstants.primaryRed),
            title: const Text('Rechercher'), onTap: () { Navigator.pop(context); _err('Bientôt disponible'); }),
        ListTile(leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(context); _err('Bientôt disponible'); }),
      ])));

  @override
  void dispose() {
    _msgCtrl.dispose(); _scroll.dispose(); _focus.dispose();
    _typingTmr?.cancel(); _recTmr?.cancel(); _pulse.dispose();
    _rec.dispose();
    _prePosStream?.cancel(); _preStateStream?.cancel();
    _prePl?.dispose();
    for (final p in _players.values) p.dispose();
    for (final c in _vCtrl.values) c.dispose();
    for (final c in _cCtrl.values) c.dispose();
    try { context.read<MessageProvider>().removeListener(_checkTyping); } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _MI extends StatelessWidget {
  final IconData icon; final Color color; final String label;
  const _MI(this.icon, this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color), const SizedBox(width: 10), Text(label),
  ]);
}