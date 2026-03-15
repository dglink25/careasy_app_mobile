import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
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
  // ─── Contrôleurs ─────────────────────────────────────────────────────────
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final Map<String, AudioPlayer> _audioPlayers = {};

  // ─── États ───────────────────────────────────────────────────────────────
  bool _isTyping = false;
  Timer? _typingDebounce;
  bool _otherUserTyping = false;
  bool _isSending = false;

  // ─── Enregistrement vocal (style WhatsApp) ────────────────────────────────
  bool _isRecording = false;
  bool _isRecordingLocked = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  double _recordSlideOffset = 0.0;
  bool _isSlidingToCancel = false;

  // ─── Localisation ─────────────────────────────────────────────────────────
  bool _isSendingLocation = false;

  // ─── Animations ───────────────────────────────────────────────────────────
  late AnimationController _pulseAnimation;

  // ─── Vidéo ────────────────────────────────────────────────────────────────
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ChewieController> _chewieControllers = {};

  // ─── Statut en ligne dynamique ────────────────────────────────────────────
  bool get _isOtherUserOnline {
    final provider = context.read<MessageProvider>();
    // Priorité au statut temps réel Pusher, sinon statut initial
    return provider.getUserOnlineStatus(widget.otherUser.id) ||
        widget.otherUser.isOnline;
  }

  DateTime? get _otherUserLastSeen {
    final provider = context.read<MessageProvider>();
    return provider.getUserLastSeen(widget.otherUser.id) ??
        widget.otherUser.lastSeen;
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _loadMessages();
    _setupListeners();
    _markAsRead();

    // S'abonner au canal de la conversation pour les événements temps réel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Configurer la navigation depuis les notifications
      NotificationService().onNotificationTap = (conversationId) {
        if (conversationId != widget.conversationId) {
          Navigator.pop(context);
        }
      };
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MessageProvider>().loadMessages(widget.conversationId);
      _markAsRead();
    }
  }

  void _loadMessages() async {
    await context.read<MessageProvider>().loadMessages(widget.conversationId);
    _scrollToBottom();
  }

  void _markAsRead() async {
    await context
        .read<MessageProvider>()
        .markConversationAsRead(widget.conversationId);
  }

  void _setupListeners() {
    // ── Listener typing ──────────────────────────────────────────────────
    _messageController.addListener(() {
      final hasText = _messageController.text.isNotEmpty;

      // Force le rebuild pour afficher/masquer le bouton envoi
      setState(() {});

      if (hasText && !_isTyping) {
        _isTyping = true;
        _sendTypingStatus(true);
      } else if (!hasText && _isTyping) {
        _isTyping = false;
        _sendTypingStatus(false);
      }

      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(seconds: 2), () {
        if (_isTyping) {
          _isTyping = false;
          _sendTypingStatus(false);
        }
      });
    });

    // ── Listener typing de l'autre utilisateur ────────────────────────────
    context.read<MessageProvider>().addListener(_checkTypingStatus);
  }

  void _checkTypingStatus() {
    if (!mounted) return;
    final isTyping = context.read<MessageProvider>().isUserTyping(
          widget.conversationId,
          widget.otherUser.id,
        );
    if (_otherUserTyping != isTyping) {
      setState(() => _otherUserTyping = isTyping);
    }
  }

  Future<void> _sendTypingStatus(bool isTyping) async {
    await context
        .read<MessageProvider>()
        .sendTypingIndicator(widget.conversationId, isTyping);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  // ─── Envoi de message ─────────────────────────────────────────────────────
  Future<void> _sendMessage({
    String? content,
    String? filePath,
    String? type,
    double? latitude,
    double? longitude,
  }) async {
    final text = content?.trim();
    if ((text == null || text.isEmpty) &&
        filePath == null &&
        (latitude == null || longitude == null)) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      String messageType;
      if (latitude != null && longitude != null) {
        messageType = 'location';
      } else {
        messageType =
            type ?? (filePath != null ? _getFileType(filePath) : 'text');
      }

      await context.read<MessageProvider>().sendMessage(
            widget.conversationId,
            type: messageType,
            content: text,
            filePath: filePath,
            latitude: latitude,
            longitude: longitude,
          );

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      debugPrint('Erreur envoi: $e');
      _showError("Impossible d'envoyer le message");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _getFileType(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return 'image';
    } else if (['mp4', 'mov', 'avi', 'mkv', '3gp', 'webm'].contains(ext)) {
      return 'video';
    } else if (['mp3', 'm4a', 'aac', 'wav', 'ogg'].contains(ext)) {
      return 'audio';
    } else {
      return 'document';
    }
  }

  // ─── PHOTOS ───────────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        await _sendMessage(filePath: image.path, type: 'image');
      }
    } catch (e) {
      _showError('Erreur prise de photo');
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        await _sendMessage(filePath: image.path, type: 'image');
      }
    } catch (e) {
      _showError('Erreur sélection image');
    }
  }

  // ─── VIDÉOS ───────────────────────────────────────────────────────────────
  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (video != null) {
        await _sendMessage(filePath: video.path, type: 'video');
      }
    } catch (e) {
      _showError('Erreur sélection vidéo');
    }
  }

  Future<void> _recordVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      );
      if (video != null) {
        await _sendMessage(filePath: video.path, type: 'video');
      }
    } catch (e) {
      _showError('Erreur enregistrement vidéo');
    }
  }

  // ─── DOCUMENTS ────────────────────────────────────────────────────────────
  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        await _sendMessage(
            filePath: result.files.single.path!, type: 'document');
      }
    } catch (e) {
      _showError('Erreur sélection fichier');
    }
  }

  // ─── LOCALISATION ────────────────────────────────────────────────────────
  Future<void> _sendLocation() async {
    setState(() => _isSendingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Permission de localisation refusée');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError('Permissions de localisation définitivement refusées');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String address =
          'Position: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          address = [
            placemarks.first.street,
            placemarks.first.locality,
            placemarks.first.country,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
        }
      } catch (_) {}

      await _sendMessage(
        content: address,
        type: 'location',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      _showError('Erreur envoi localisation');
    } finally {
      if (mounted) setState(() => _isSendingLocation = false);
    }
  }

  // ─── ENREGISTREMENT VOCAL ─────────────────────────────────────────────────
  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showError('Permission microphone refusée');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _isRecordingLocked = false;
        _recordDuration = Duration.zero;
        _recordSlideOffset = 0.0;
        _isSlidingToCancel = false;
      });

      _recordTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isRecording && mounted) {
          setState(() {
            _recordDuration =
                Duration(seconds: _recordDuration.inSeconds + 1);
          });
        }
      });
    } catch (e) {
      debugPrint('Erreur démarrage enregistrement: $e');
      _showError('Impossible de démarrer l\'enregistrement');
    }
  }

  Future<void> _stopRecording({bool send = true}) async {
    try {
      final path = await _audioRecorder.stop();
      _recordTimer?.cancel();

      if (mounted) {
        setState(() {
          _isRecording = false;
          _isRecordingLocked = false;
          _recordSlideOffset = 0.0;
          _isSlidingToCancel = false;
        });
      }

      if (send && path != null && path.isNotEmpty) {
        if (_recordDuration.inSeconds >= 1) {
          await _sendMessage(filePath: path, type: 'audio');
        } else {
          _showError('Enregistrement trop court (min. 1 seconde)');
          File(path).deleteSync();
        }
      } else if (path != null && File(path).existsSync()) {
        File(path).deleteSync();
      }
    } catch (e) {
      debugPrint('Erreur arrêt enregistrement: $e');
    }
  }

  void _cancelRecording() => _stopRecording(send: false);
  void _lockRecording() => setState(() => _isRecordingLocked = true);

  void _handleRecordSlideUpdate(DragUpdateDetails details) {
    if (!_isRecording || _isRecordingLocked) return;
    setState(() {
      _recordSlideOffset += details.delta.dx;
      _isSlidingToCancel = _recordSlideOffset < -50;
    });
  }

  void _handleRecordSlideEnd(DragEndDetails details) {
    if (!_isRecording) return;
    if (_isSlidingToCancel) {
      _cancelRecording();
    } else if (!_isRecordingLocked) {
      _stopRecording(send: true);
    }
  }

  // ─── LECTURE AUDIO ────────────────────────────────────────────────────────
  Future<void> _playAudio(String messageId, String fileUrl) async {
    try {
      for (final entry in _audioPlayers.entries) {
        if (entry.key != messageId && entry.value.playing) {
          await entry.value.stop();
        }
      }

      AudioPlayer? player = _audioPlayers[messageId];
      if (player == null) {
        player = AudioPlayer();
        _audioPlayers[messageId] = player;
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) setState(() {});
          }
        });
      }

      if (player.playing) {
        await player.pause();
      } else {
        await player.setUrl(fileUrl);
        await player.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showError('Impossible de lire l\'audio');
    }
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ─── LECTURE VIDÉO ────────────────────────────────────────────────────────
  Future<void> _initVideoPlayer(String messageId, String videoUrl) async {
    if (_videoControllers.containsKey(messageId)) return;

    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await controller.initialize();

      final chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio,
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, msg) =>
            const Center(child: Icon(Icons.error, color: Colors.red)),
      );

      if (mounted) {
        setState(() {
          _videoControllers[messageId] = controller;
          _chewieControllers[messageId] = chewieController;
        });
      }
    } catch (e) {
      debugPrint('Erreur init vidéo: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD PRINCIPAL
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: _buildAppBarTitle(),
        actions: [
          IconButton(icon: const Icon(Icons.phone), onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showOptionsMenu),
        ],
      ),
      body: Column(
        children: [
          if (widget.serviceName != null) _buildServiceInfoBanner(),
          Expanded(
            child: Consumer<MessageProvider>(
              builder: (context, provider, child) {
                final messages =
                    provider.getMessages(widget.conversationId);

                if (provider.isLoading && messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryRed),
                  );
                }

                if (messages.isEmpty) return _buildEmptyState();

                // Scroll automatique à chaque nouveau message
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom(animated: false);
                });

                return _buildMessagesList(messages);
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  // ─── APP BAR ─────────────────────────────────────────────────────────────
  Widget _buildAppBarTitle() {
    return Consumer<MessageProvider>(
      builder: (context, provider, _) {
        final isOnline = provider.getUserOnlineStatus(widget.otherUser.id) ||
            widget.otherUser.isOnline;
        final lastSeen = provider.getUserLastSeen(widget.otherUser.id) ??
            widget.otherUser.lastSeen;

        return Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  backgroundImage: widget.otherUser.photoUrl != null
                      ? NetworkImage(widget.otherUser.photoUrl!)
                      : null,
                  child: widget.otherUser.photoUrl == null
                      ? Text(
                          widget.otherUser.name.isNotEmpty
                              ? widget.otherUser.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryRed,
                          ),
                        )
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (_otherUserTyping)
                    const Text(
                      'En train d\'écrire...',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    )
                  else if (isOnline)
                    const Text(
                      'En ligne',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    )
                  else if (lastSeen != null)
                    Text(
                      'Vu ${_formatLastSeen(lastSeen)}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatLastSeen(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return DateFormat('dd/MM/yy HH:mm').format(date);
  }

  // ─── LISTE DE MESSAGES ────────────────────────────────────────────────────
  Widget _buildMessagesList(List<MessageModel> messages) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final showDate = index == 0 ||
            messages[index].createdAt.day !=
                messages[index - 1].createdAt.day;
        return Column(
          children: [
            if (showDate) _buildDateSeparator(message.createdAt),
            _buildMessageBubble(message),
          ],
        );
      },
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String text;
    if (now.difference(date).inDays == 0) {
      text = "Aujourd'hui";
    } else if (now.difference(date).inDays == 1) {
      text = 'Hier';
    } else {
      text = DateFormat('dd MMMM yyyy', 'fr_FR').format(date);
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        ),
      ),
    );
  }

  // ─── BULLE DE MESSAGE ─────────────────────────────────────────────────────
  Widget _buildMessageBubble(MessageModel message) {
    // isMe est calculé correctement dans MessageModel.fromJson
    final isMe = message.isMe;
    final isError = message.status == 'error';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar à gauche pour l'autre utilisateur
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.grey[200],
                backgroundImage: widget.otherUser.photoUrl != null
                    ? NetworkImage(widget.otherUser.photoUrl!)
                    : null,
                child: widget.otherUser.photoUrl == null
                    ? Text(
                        widget.otherUser.name.isNotEmpty
                            ? widget.otherUser.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 10, color: AppConstants.primaryRed),
                      )
                    : null,
              ),
            ),

          // Bulle
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                // Mes messages = rouge CarEasy, messages reçus = blanc
                color: isError
                    ? Colors.red[50]
                    : isMe
                        ? AppConstants.primaryRed
                        : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: isError ? Border.all(color: Colors.red) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contenu média si non-texte
                  if (message.type != 'text')
                    _buildMediaContent(message),

                  // Texte (sauf pour location et audio qui ont leur propre affichage)
                  if (message.content.isNotEmpty &&
                      message.type != 'location' &&
                      message.type != 'audio' &&
                      message.type != 'vocal')
                    Padding(
                      padding: EdgeInsets.only(
                          top: message.type != 'text' ? 6 : 0),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  const SizedBox(height: 3),

                  // Heure + statut
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.createdAt),
                        style: TextStyle(
                          color: isError
                              ? Colors.red
                              : isMe
                                  ? Colors.white60
                                  : Colors.grey[500],
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        _buildMessageStatus(message),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Espace à droite pour mes messages
          if (isMe) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildMessageStatus(MessageModel message) {
    if (message.status == 'sending') {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
            color: Colors.white60, strokeWidth: 1.5),
      );
    }
    if (message.status == 'error') {
      return const Icon(Icons.error_outline, color: Colors.red, size: 12);
    }
    return Icon(
      message.readAt != null ? Icons.done_all : Icons.done,
      size: 12,
      color: message.readAt != null ? Colors.lightBlue[200] : Colors.white60,
    );
  }

  // ─── CONTENU MÉDIA ────────────────────────────────────────────────────────
  Widget _buildMediaContent(MessageModel message) {
    switch (message.type) {
      case 'image':
        if (message.fileUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _showFullScreenImage(message.fileUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              message.fileUrl!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Center(
                          child: CircularProgressIndicator()),
                    ),
              errorBuilder: (_, __, ___) => Container(
                height: 200,
                color: Colors.grey[300],
                child: const Center(
                    child: Icon(Icons.broken_image, size: 40)),
              ),
            ),
          ),
        );

      case 'video':
        if (message.fileUrl == null) return const SizedBox.shrink();
        return _buildVideoPlayer(message);

      case 'location':
        return GestureDetector(
          onTap: () => _openLocation(
              message.latitude ?? 0, message.longitude ?? 0),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: message.isMe ? Colors.red[400] : Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on,
                    color: message.isMe ? Colors.white : Colors.blue[700],
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content.isNotEmpty
                            ? message.content
                            : 'Localisation',
                        style: TextStyle(
                          color: message.isMe
                              ? Colors.white
                              : Colors.blue[800],
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Appuyer pour ouvrir',
                        style: TextStyle(
                          fontSize: 10,
                          color: message.isMe
                              ? Colors.white70
                              : Colors.blue[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 10,
                    color: message.isMe
                        ? Colors.white70
                        : Colors.blue[400]),
              ],
            ),
          ),
        );

      case 'audio':
      case 'vocal':
        return _buildAudioPlayer(message);

      case 'document':
        if (message.fileUrl == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _openFile(message.fileUrl!),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: message.isMe ? Colors.red[400] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(message.fileUrl!),
                  color: message.isMe ? Colors.white : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.fileUrl!.split('/').last,
                    style: TextStyle(
                      color:
                          message.isMe ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.download,
                    size: 18,
                    color: message.isMe ? Colors.white : Colors.grey[600]),
              ],
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAudioPlayer(MessageModel message) {
    final player = _audioPlayers[message.id];
    final isPlaying = player?.playing ?? false;

    return StreamBuilder<Duration>(
      stream: player?.positionStream ?? const Stream.empty(),
      builder: (context, posSnapshot) {
        final position = posSnapshot.data ?? Duration.zero;
        final duration = player?.duration ?? Duration.zero;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: message.isMe ? Colors.red[600] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  if (message.fileUrl != null) {
                    _playAudio(message.id, message.fileUrl!);
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: message.isMe ? Colors.white24 : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: message.isMe
                        ? Colors.white
                        : AppConstants.primaryRed,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10),
                        trackHeight: 2,
                        thumbColor: message.isMe
                            ? Colors.white
                            : AppConstants.primaryRed,
                        activeTrackColor: message.isMe
                            ? Colors.white
                            : AppConstants.primaryRed,
                        inactiveTrackColor: message.isMe
                            ? Colors.white38
                            : Colors.grey[300],
                      ),
                      child: Slider(
                        value: duration.inMilliseconds > 0
                            ? position.inMilliseconds /
                                duration.inMilliseconds
                            : 0.0,
                        onChanged: (val) {
                          player?.seek(Duration(
                              milliseconds:
                                  (val * duration.inMilliseconds)
                                      .toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: TextStyle(
                              fontSize: 9,
                              color: message.isMe
                                  ? Colors.white70
                                  : Colors.grey[600],
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              fontSize: 9,
                              color: message.isMe
                                  ? Colors.white70
                                  : Colors.grey[600],
                            ),
                          ),
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

  Widget _buildVideoPlayer(MessageModel message) {
    if (!_chewieControllers.containsKey(message.id)) {
      _initVideoPlayer(message.id, message.fileUrl!);
      return Container(
        height: 180,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      height: 180,
      child: Chewie(controller: _chewieControllers[message.id]!),
    );
  }

  // ─── BARRE DE SAISIE ──────────────────────────────────────────────────────
  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRecording) _buildRecordingIndicator(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Bouton pièces jointes
              _buildAttachmentButton(),

              // Champ de texte
              Expanded(child: _buildTextField()),

              const SizedBox(width: 6),

              // Bouton envoi / micro
              _buildSendOrMicButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(22),
      ),
      child: TextField(
        controller: _messageController,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: 'Votre message...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        enabled: !_isSending && !_isRecording,
      ),
    );
  }

  /// ⭐ BOUTON ENVOI / MICRO — corrigé avec setState dans le listener
  Widget _buildSendOrMicButton() {
    final hasText = _messageController.text.trim().isNotEmpty;

    if (hasText || _isSending) {
      // ── Bouton ENVOI ──────────────────────────────────────────────────
      return GestureDetector(
        onTap: _isSending
            ? null
            : () => _sendMessage(content: _messageController.text),
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppConstants.primaryRed,
            shape: BoxShape.circle,
          ),
          child: _isSending
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.send, color: Colors.white, size: 20),
        ),
      );
    }

    if (_isRecording && _isRecordingLocked) {
      // ── En cours verrouillé → bouton ENVOYER l'enregistrement ────────
      return GestureDetector(
        onTap: () => _stopRecording(send: true),
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.send, color: Colors.white, size: 20),
        ),
      );
    }

    // ── Bouton MICRO (appui long pour enregistrer) ───────────────────
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) {
        if (_isRecording && !_isRecordingLocked) {
          _stopRecording(send: true);
        }
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _isRecording
              ? Colors.red[700]
              : AppConstants.primaryRed,
          shape: BoxShape.circle,
        ),
        child: _isRecording
            ? AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) => Icon(
                  Icons.mic,
                  color: Colors.white.withOpacity(
                      0.5 + 0.5 * _pulseAnimation.value),
                  size: 20,
                ),
              )
            : const Icon(Icons.mic, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return GestureDetector(
      onHorizontalDragUpdate: _handleRecordSlideUpdate,
      onHorizontalDragEnd: _handleRecordSlideEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 50,
        decoration: BoxDecoration(
          color: _isSlidingToCancel ? Colors.red[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            // Point rouge animé
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(
                        0.5 + 0.5 * _pulseAnimation.value),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatDuration(_recordDuration),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500),
            ),
            Expanded(
              child: Center(
                child: Text(
                  _isSlidingToCancel
                      ? '✕ Annuler'
                      : '← Glisser pour annuler',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        _isSlidingToCancel ? Colors.red : Colors.grey[500],
                  ),
                ),
              ),
            ),
            // Cadenas
            if (!_isRecordingLocked)
              GestureDetector(
                onTap: _lockRecording,
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.lock_open,
                      size: 18, color: Colors.grey[500]),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.lock,
                    size: 18, color: AppConstants.primaryRed),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentButton() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.attach_file,
          color: AppConstants.primaryRed, size: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'camera':
            _takePhoto();
          case 'image':
            _pickImage();
          case 'video':
            _pickVideo();
          case 'record_video':
            _recordVideo();
          case 'document':
            _pickDocument();
          case 'location':
            _sendLocation();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'camera',
          child: Row(children: [
            Icon(Icons.camera_alt, color: Colors.blue),
            SizedBox(width: 10),
            Text('Prendre une photo'),
          ]),
        ),
        const PopupMenuItem(
          value: 'image',
          child: Row(children: [
            Icon(Icons.image, color: Colors.green),
            SizedBox(width: 10),
            Text('Choisir une image'),
          ]),
        ),
        const PopupMenuItem(
          value: 'video',
          child: Row(children: [
            Icon(Icons.video_library, color: Colors.purple),
            SizedBox(width: 10),
            Text('Choisir une vidéo'),
          ]),
        ),
        const PopupMenuItem(
          value: 'record_video',
          child: Row(children: [
            Icon(Icons.videocam, color: Colors.red),
            SizedBox(width: 10),
            Text('Enregistrer une vidéo'),
          ]),
        ),
        const PopupMenuItem(
          value: 'document',
          child: Row(children: [
            Icon(Icons.insert_drive_file, color: Colors.orange),
            SizedBox(width: 10),
            Text('Document'),
          ]),
        ),
        PopupMenuItem(
          value: 'location',
          enabled: !_isSendingLocation,
          child: Row(children: [
            Icon(Icons.location_on, color: Colors.red),
            const SizedBox(width: 10),
            Text(_isSendingLocation ? 'Envoi...' : 'Localisation'),
          ]),
        ),
      ],
    );
  }

  // ─── DIVERS ───────────────────────────────────────────────────────────────
  Widget _buildServiceInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: Colors.orange[50],
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'À propos de: ${widget.serviceName}',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 14),
          Text(
            'Aucun message',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.grey[500]),
          ),
          const SizedBox(height: 6),
          Text(
            'Envoyez votre premier message',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.network(imageUrl)),
          ),
        ),
      ),
    );
  }

  Future<void> _openLocation(double lat, double lng) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('Impossible d\'ouvrir la localisation');
    }
  }

  Future<void> _openFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('Impossible d\'ouvrir le fichier');
    }
  }

  IconData _getFileIcon(String url) {
    final ext = url.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.search, color: AppConstants.primaryRed),
              title: const Text('Rechercher dans la conversation'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoon('Recherche');
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off,
                  color: AppConstants.primaryRed),
              title: const Text('Désactiver les notifications'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoon('Notifications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Supprimer la conversation',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showComingSoon('Suppression');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Bientôt disponible'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();
    _pulseAnimation.dispose();
    _audioRecorder.dispose();
    for (final p in _audioPlayers.values) {
      p.dispose();
    }
    for (final c in _videoControllers.values) {
      c.dispose();
    }
    for (final c in _chewieControllers.values) {
      c.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}