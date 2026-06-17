import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../utils/constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  MODAL IMAGE — zoom, partage, téléchargement
// ═══════════════════════════════════════════════════════════════════════════

class ImageViewerModal extends StatefulWidget {
  final String url;
  final String? heroTag;

  const ImageViewerModal({super.key, required this.url, this.heroTag});

  /// Ouvre le modal en full-screen (sans barre de navigation)
  static Future<void> show(BuildContext context, String url,
      {String? heroTag}) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            ImageViewerModal(url: url, heroTag: heroTag),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<ImageViewerModal> createState() => _ImageViewerModalState();
}

class _ImageViewerModalState extends State<ImageViewerModal> {
  bool _showBars  = true;
  bool _downloading = false;

  void _toggleBars() => setState(() => _showBars = !_showBars);

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final resp = await http.get(Uri.parse(widget.url));
      if (resp.statusCode == 200) {
        final dir  = await getTemporaryDirectory();
        final ext  = widget.url.split('.').last.split('?').first;
        final file = File(
            '${dir.path}/careasy_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await file.writeAsBytes(resp.bodyBytes);
        await Share.shareXFiles([XFile(file.path)],
            text: 'Image partagée depuis CarEasy');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de télécharger')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocalFile = !widget.url.startsWith('http');
    final imageWidget = isLocalFile
        ? Image.file(File(widget.url), fit: BoxFit.contain)
        : Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  SizedBox(height: 12),
                  Text('Impossible de charger l\'image',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Image zoomable ────────────────────────────────────────
            GestureDetector(
              onTap: _toggleBars,
              child: widget.heroTag != null
                  ? Hero(
                      tag: widget.heroTag!,
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5.0,
                        child: Center(child: imageWidget),
                      ),
                    )
                  : InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5.0,
                      child: Center(child: imageWidget),
                    ),
            ),

            // ── Barre top ─────────────────────────────────────────────
            AnimatedOpacity(
              opacity: _showBars ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    foregroundColor: Colors.white,
                    title: const Text('Image',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    actions: [
                      if (!isLocalFile)
                        _downloading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2)))
                            : IconButton(
                                icon: const Icon(Icons.share_outlined,
                                    color: Colors.white),
                                onPressed: _download,
                                tooltip: 'Partager',
                              ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MODAL VIDÉO — plein écran, contrôles, partage
// ═══════════════════════════════════════════════════════════════════════════

class VideoViewerModal extends StatefulWidget {
  final String url;
  final String? heroTag;

  const VideoViewerModal({super.key, required this.url, this.heroTag});

  static Future<void> show(BuildContext context, String url,
      {String? heroTag}) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            VideoViewerModal(url: url, heroTag: heroTag),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<VideoViewerModal> createState() => _VideoViewerModalState();
}

class _VideoViewerModalState extends State<VideoViewerModal> {
  VideoPlayerController? _vpc;
  ChewieController?      _cc;
  bool _loading = true;
  bool _error   = false;

  @override
  void initState() {
    super.initState();
    // Force landscape en plein écran vidéo
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final isLocal = !widget.url.startsWith('http');
      final vpc = isLocal
          ? VideoPlayerController.file(File(widget.url))
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await vpc.initialize();
      final cc = ChewieController(
        videoPlayerController: vpc,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppConstants.primaryRed,
          handleColor: AppConstants.primaryRed,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
        errorBuilder: (_, msg) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(msg,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryRed),
              ),
            ],
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _vpc = vpc;
          _cc  = cc;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  void _retry() {
    setState(() { _loading = true; _error = false; });
    _vpc?.dispose();
    _cc?.dispose();
    _vpc = null;
    _cc  = null;
    _initVideo();
  }

  @override
  void dispose() {
    // Restaurer portrait uniquement
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _vpc?.dispose();
    _cc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Vidéo',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (!widget.url.startsWith('http') == false &&
              widget.url.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              onPressed: () async {
                final uri = Uri.parse(widget.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: Center(
        child: _loading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Chargement de la vidéo…',
                      style: TextStyle(color: Colors.white70)),
                ],
              )
            : _error
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      const Text('Impossible de lire la vidéo',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryRed),
                      ),
                    ],
                  )
                : _cc != null
                    ? Chewie(controller: _cc!)
                    : const SizedBox.shrink(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MODAL AUDIO — lecteur vocal plein écran style WhatsApp
// ═══════════════════════════════════════════════════════════════════════════

class AudioPlayerModal extends StatefulWidget {
  final String url;
  final String senderName;
  final String? senderPhotoUrl;
  final bool isMe;

  const AudioPlayerModal({
    super.key,
    required this.url,
    required this.senderName,
    required this.isMe,
    this.senderPhotoUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required String url,
    required String senderName,
    required bool isMe,
    String? senderPhotoUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioPlayerModal(
        url: url,
        senderName: senderName,
        isMe: isMe,
        senderPhotoUrl: senderPhotoUrl,
      ),
    );
  }

  @override
  State<AudioPlayerModal> createState() => _AudioPlayerModalState();
}

class _AudioPlayerModalState extends State<AudioPlayerModal> {
  final AudioPlayer _player = AudioPlayer();
  bool     _loading  = true;
  bool     _error    = false;
  bool     _playing  = false;
  Duration _pos      = Duration.zero;
  Duration _dur      = Duration.zero;
  double   _speed    = 1.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      _dur = _player.duration ?? Duration.zero;
      _player.positionStream.listen((d) {
        if (mounted) setState(() => _pos = d);
      });
      _player.playerStateStream.listen((s) {
        if (mounted) setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed && mounted) {
          setState(() { _playing = false; _pos = Duration.zero; });
        }
      });
      _player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _dur = d);
      });
      if (mounted) setState(() => _loading = false);
      // Auto-play à l'ouverture
      await _player.play();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _changeSpeed() async {
    setState(() {
      _speed = _speed == 1.0 ? 1.5 : _speed == 1.5 ? 2.0 : 1.0;
    });
    await _player.setSpeed(_speed);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _dur.inMilliseconds > 0
        ? (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pill handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Avatar + nom
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppConstants.primaryRed.withOpacity(0.1),
              backgroundImage: widget.senderPhotoUrl != null
                  ? NetworkImage(widget.senderPhotoUrl!) : null,
              child: widget.senderPhotoUrl == null
                  ? Icon(Icons.person,
                      color: AppConstants.primaryRed, size: 24) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isMe ? 'Vous' : widget.senderName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Text('Message vocal',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            // Vitesse lecture
            GestureDetector(
              onTap: _changeSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_speed == 1.0 ? "1" : _speed == 1.5 ? "1.5" : "2"}×',
                  style: const TextStyle(
                    color: AppConstants.primaryRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                  color: AppConstants.primaryRed),
            )
          else if (_error)
            Column(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.red, size: 40),
                const SizedBox(height: 8),
                const Text('Impossible de lire ce message vocal'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _error = false; _loading = true; });
                    _init();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryRed),
                ),
              ],
            )
          else ...[
            // ── Slider progression ───────────────────────────────
            SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7),
                trackHeight: 4,
                thumbColor: AppConstants.primaryRed,
                activeTrackColor: AppConstants.primaryRed,
                inactiveTrackColor: Colors.grey[300],
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: pct.toDouble(),
                onChanged: (v) => _player.seek(Duration(
                    milliseconds:
                        (v * _dur.inMilliseconds).toInt())),
              ),
            ),

            // ── Temps ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_pos),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600])),
                  Text(_fmt(_dur),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Bouton play/pause central ─────────────────────────
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryRed.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MODAL DOCUMENT — aperçu + téléchargement/partage
// ═══════════════════════════════════════════════════════════════════════════

class DocumentViewerModal extends StatefulWidget {
  final String url;
  final String fileName;

  const DocumentViewerModal(
      {super.key, required this.url, required this.fileName});

  static Future<void> show(
      BuildContext context, String url, String fileName) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) =>
          DocumentViewerModal(url: url, fileName: fileName),
    );
  }

  @override
  State<DocumentViewerModal> createState() => _DocumentViewerModalState();
}

class _DocumentViewerModalState extends State<DocumentViewerModal> {
  bool _downloading = false;

  String get _ext =>
      p.extension(widget.fileName).toLowerCase().replaceAll('.', '');

  IconData get _icon {
    switch (_ext) {
      case 'pdf':           return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':          return Icons.description;
      case 'xls':
      case 'xlsx':          return Icons.table_chart;
      case 'ppt':
      case 'pptx':          return Icons.slideshow;
      case 'zip':
      case 'rar':           return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'aac':           return Icons.audio_file;
      default:              return Icons.insert_drive_file;
    }
  }

  Color get _color {
    switch (_ext) {
      case 'pdf':   return Colors.red;
      case 'doc':
      case 'docx':  return const Color(0xFF2B579A);
      case 'xls':
      case 'xlsx':  return const Color(0xFF217346);
      case 'ppt':
      case 'pptx':  return const Color(0xFFD24726);
      default:      return Colors.grey[700]!;
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadAndShare() async {
    setState(() => _downloading = true);
    try {
      final resp = await http.get(Uri.parse(widget.url));
      if (resp.statusCode == 200) {
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.fileName}');
        await file.writeAsBytes(resp.bodyBytes);
        await Share.shareXFiles([XFile(file.path)],
            text: 'Document partagé depuis CarEasy');
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de télécharger')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pill handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icône document grande
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(_icon, color: _color, size: 44),
          ),
          const SizedBox(height: 16),

          // Nom fichier
          Text(
            widget.fileName,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _ext.toUpperCase(),
            style: TextStyle(
                color: _color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 28),

          // Boutons actions
          Row(children: [
            // Ouvrir
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ouvrir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primaryRed,
                  side: const BorderSide(color: AppConstants.primaryRed),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Télécharger / Partager
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _downloading ? null : _downloadAndShare,
                icon: _downloading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.share_outlined),
                label: Text(_downloading ? 'Téléchargement…' : 'Partager'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
