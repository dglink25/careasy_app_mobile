import 'dart:io';
import 'dart:math';
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
import '../providers/message_provider.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geocoding/geocoding.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  // Contrôleurs
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final Map<String, AudioPlayer> _audioPlayers = {};
  
  // États
  bool _isTyping = false;
  Timer? _typingDebounce;
  bool _otherUserTyping = false;
  bool _isSending = false;
  
  // États pour l'audio (style WhatsApp)
  bool _isRecording = false;
  bool _isRecordingLocked = false;
  String? _recordingPath;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  double _recordSlideOffset = 0.0;
  bool _isSlidingToCancel = false;
  
  // États pour la localisation
  bool _isSendingLocation = false;
  
  // Animation pour l'enregistrement
  late AnimationController _pulseAnimation;
  late AnimationController _slideAnimation;
  
  // Notifications locales
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // Videos
  Map<String, VideoPlayerController> _videoControllers = {};
  Map<String, ChewieController> _chewieControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialiser les animations
    _pulseAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _slideAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    // Initialiser les notifications
    _initNotifications();
    
    // Charger les messages
    _loadMessages();
    _setupListeners();
    _markAsRead();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings = 
        DarwinInitializationSettings();
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Gérer le tap sur la notification
      },
    );
  }

  void _showLocalNotification(String title, String body) {
    _notifications.show(
      Random().nextInt(1000),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages_channel',
          'Messages',
          channelDescription: 'Notifications de messages',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          sound: 'default',
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MessageProvider>().loadMessages(widget.conversationId);
      _markAsRead();
    } else if (state == AppLifecycleState.paused) {
      // L'app est en arrière-plan
    }
  }

  void _loadMessages() async {
    await context.read<MessageProvider>().loadMessages(widget.conversationId);
    _scrollToBottom();
  }

  void _markAsRead() async {
    await context.read<MessageProvider>().markConversationAsRead(widget.conversationId);
  }

  void _setupListeners() {
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _sendTypingStatus(true);
      }
    });

    _messageController.addListener(() {
      if (_messageController.text.isNotEmpty && !_isTyping) {
        _isTyping = true;
        _sendTypingStatus(true);
      } else if (_messageController.text.isEmpty && _isTyping) {
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
    await context.read<MessageProvider>().sendTypingIndicator(
      widget.conversationId,
      isTyping,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), // CORRIGÉ: milliseconds au lieu de milestones
          curve: Curves.easeOut,
        );
      }
    });
  }


  Future<void> _sendMessage({
    String? content, 
    String? filePath, 
    String? type, 
    double? latitude, 
    double? longitude,
    File? file,
  }) async {
    if ((content == null || content.isEmpty) && filePath == null && file == null && (latitude == null || longitude == null)) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      // ADAPTATION: Déterminer le type pour l'API
      String messageType;
      if (latitude != null && longitude != null) {
        messageType = 'location'; // Sera converti en 'text' par le provider
      } else {
        messageType = type ?? 
            (filePath != null ? _getFileType(filePath) : 
            (file != null ? _getFileType(file.path) : 'text'));
      }

      String? pathToSend = filePath ?? file?.path;

      await context.read<MessageProvider>().sendMessage(
        widget.conversationId,
        type: messageType,
        content: content,
        filePath: pathToSend,
        latitude: latitude,
        longitude: longitude,
      );

      _messageController.clear();
      
    } catch (e) {
      print('Erreur envoi message: $e');
      _showError("Impossible d'envoyer le message");
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _getFileType(String path) {
    final extension = path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      return 'image';
    } else if (['mp4', 'mov', 'avi', 'mkv', '3gp', 'webm'].contains(extension)) {
      return 'video';
    } else if (['mp3', 'm4a', 'aac', 'wav', 'm4a', 'ogg'].contains(extension)) {
      return 'audio'; // Sera converti en 'vocal' par le provider
    } else {
      return 'document';
    }
  }

  // ==================== MESSAGE BUBBLE CORRIGÉE ====================
  Widget _buildMessageBubble(MessageModel message) {
    final isMe = message.isMe;
    final timeFormat = DateFormat('HH:mm');
    final isError = message.status == 'error';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) _buildAvatar(),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isError 
                    ? Colors.red[50]
                    : (isMe ? const Color(0xFFE53935) : Colors.white), // Rouge pour moi, blanc pour l'autre
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: isError ? Border.all(color: Colors.red) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.type != 'text') _buildMediaContent(message),
                  if (message.content.isNotEmpty && message.type != 'location' && message.type != 'audio')
                    Padding(
                      padding: EdgeInsets.only(
                        top: message.type != 'text' ? 8 : 0,
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeFormat.format(message.createdAt),
                        style: TextStyle(
                          color: isError 
                              ? Colors.red
                              : (isMe ? Colors.white70 : Colors.grey[500]),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (isMe) _buildMessageStatus(message),
                      if (isError)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.error,
                            color: Colors.red,
                            size: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildMessageStatus(MessageModel message) {
    if (message.status == 'sending') {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          color: Colors.white70,
          strokeWidth: 2,
        ),
      );
    }
    
    // Double coche bleue pour les messages lus
    return Icon(
      message.readAt != null ? Icons.done_all : Icons.done,
      size: 12,
      color: message.readAt != null ? Colors.lightBlue : Colors.white70,
    );
  }

  // ==================== MEDIA CONTENT ====================
  Widget _buildMediaContent(MessageModel message) {
    switch (message.type) {
      case 'image':
        return GestureDetector(
          onTap: () => _showFullScreenImage(message.fileUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              message.fileUrl!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(Icons.broken_image, size: 40),
                  ),
                );
              },
            ),
          ),
        );
      
      case 'video':
        return _buildVideoPlayer(message);
      
      case 'location':
        return GestureDetector(
          onTap: () => _openLocation(
            message.latitude ?? 0,
            message.longitude ?? 0,
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue[700]),
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
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${message.latitude?.toStringAsFixed(6)}, ${message.longitude?.toStringAsFixed(6)}',
                        style: TextStyle(
                          color: Colors.blue[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 12, color: Colors.blue[400]),
              ],
            ),
          ),
        );
      
      case 'audio':
      case 'vocal': // Accepter les deux types
        return _buildAudioPlayer(message);
      
      case 'document':
        return GestureDetector(
          onTap: () => _openFile(message.fileUrl!),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(message.fileUrl!),
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileUrl?.split('/').last ?? 'Document',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getFileSize(message.fileUrl),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.download, size: 18, color: Colors.grey[600]),
              ],
            ),
          ),
        );
      
      default:
        return const SizedBox.shrink();
    }
  }

  // ==================== TEXT FIELD CORRIGÉ ====================
  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: _messageController,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: 'Votre message...',
          hintStyle: TextStyle(color: Colors.grey[500]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        maxLines: null,
        textInputAction: TextInputAction.newline, // CHANGÉ: send -> newline
        keyboardType: TextInputType.multiline,
        onSubmitted: (value) {
          // Ne pas envoyer avec Entrée
        },
        enabled: !_isSending && !_isRecording,
      ),
    );
  }

  // ==================== WHATSAPP SEND BUTTON CORRIGÉ ====================
  Widget _buildWhatsAppSendButton() {
    if (_messageController.text.isNotEmpty) {
      // Si du texte est saisi, afficher le bouton d'envoi
      return Container(
        margin: const EdgeInsets.only(left: 4),
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
        child: _isSending
            ? const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: () => _sendMessage(content: _messageController.text),
              ),
      );
    } else if (_isRecording) {
      // Si on enregistre, afficher un indicateur
      return Container(
        margin: const EdgeInsets.only(left: 4),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.mic,
          color: Colors.white,
          size: 20,
        ),
      );
    } else {
      // Sinon, afficher le bouton micro avec comportement WhatsApp
      return GestureDetector(
        onLongPress: _startRecording,
        onLongPressUp: () {
          if (_isRecording && !_isRecordingLocked) {
            _stopRecording(send: true);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mic,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    }
  }

  // ==================== IMAGES ====================
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        await _sendMessage(
          filePath: image.path,
          type: 'image',
        );
      }
    } catch (e) {
      _showError('Erreur lors de la sélection de l\'image');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        await _sendMessage(
          filePath: image.path,
          type: 'image',
        );
      }
    } catch (e) {
      _showError('Erreur lors de la prise de photo');
    }
  }

  // ==================== VIDEOS ====================
  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        await _sendMessage(
          filePath: video.path,
          type: 'video',
        );
      }
    } catch (e) {
      _showError('Erreur lors de la sélection de la vidéo');
    }
  }

  Future<void> _recordVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      );

      if (video != null) {
        await _sendMessage(
          filePath: video.path,
          type: 'video',
        );
      }
    } catch (e) {
      _showError('Erreur lors de l\'enregistrement de la vidéo');
    }
  }

  // ==================== DOCUMENTS ====================
  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        await _sendMessage(
          filePath: result.files.single.path!,
          type: 'document',
        );
      }
    } catch (e) {
      _showError('Erreur lors de la sélection du fichier');
    }
  }
  
  // ==================== LOCALISATION ====================
  Future<void> _sendLocation() async {
    setState(() => _isSendingLocation = true);

    try {
      // Vérifier les permissions
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

      // Obtenir la position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Obtenir l'adresse
      String address = 'Position: ${position.latitude}, ${position.longitude}';
      
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          address = [
            placemarks.first.street,
            placemarks.first.locality,
            placemarks.first.country,
          ].where((e) => e != null).join(', ');
        }
      } catch (e) {
        print('Erreur récupération adresse: $e');
      }

      await _sendMessage(
        content: address,
        type: 'location',
        latitude: position.latitude,
        longitude: position.longitude,
      );

    } catch (e) {
      _showError('Erreur lors de l\'envoi de la localisation');
    } finally {
      setState(() => _isSendingLocation = false);
    }
  }

  // ==================== AUDIO (STYLE WHATSAPP) ====================
  Future<void> _startRecording() async {
    try {
      // Demander la permission
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showError('Permission d\'enregistrement refusée');
        return;
      }

      // Obtenir le répertoire temporaire
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Commencer l'enregistrement
      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _isRecordingLocked = false;
        _recordingPath = filePath;
        _recordDuration = Duration.zero;
        _recordSlideOffset = 0.0;
        _isSlidingToCancel = false;
      });

      // Démarrer le timer
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isRecording) {
          setState(() {
            _recordDuration = Duration(seconds: _recordDuration.inSeconds + 1);
          });
        }
      });

      // Animation de slide
      _slideAnimation.forward();

    } catch (e) {
      print('Erreur démarrage enregistrement: $e');
      _showError('Erreur lors du démarrage de l\'enregistrement');
    }
  }

  Future<void> _stopRecording({bool send = true}) async {
    try {
      final path = await _audioRecorder.stop();
      _recordTimer?.cancel();
      _slideAnimation.reverse();

      setState(() {
        _isRecording = false;
        _isRecordingLocked = false;
      });

      if (send && path != null && path.isNotEmpty) {
        // Vérifier la durée minimum (1 seconde)
        if (_recordDuration.inSeconds >= 1) {
          await _sendMessage(
            filePath: path,
            type: 'audio',
          );
        } else {
          _showError('Enregistrement trop court (minimum 1 seconde)');
          // Supprimer le fichier trop court
          File(path).delete();
        }
      } else if (path != null) {
        // Annulation, supprimer le fichier
        File(path).delete();
      }
    } catch (e) {
      print('Erreur arrêt enregistrement: $e');
      _showError('Erreur lors de l\'arrêt de l\'enregistrement');
    }
  }

  void _cancelRecording() {
    _stopRecording(send: false);
  }

  void _lockRecording() {
    setState(() {
      _isRecordingLocked = true;
    });
  }

  void _handleRecordSlideUpdate(DragUpdateDetails details) {
    if (!_isRecording || _isRecordingLocked) return;

    setState(() {
      _recordSlideOffset += details.delta.dx;
      
      // Si on slide suffisamment vers la gauche, on annule
      if (_recordSlideOffset < -50) {
        _isSlidingToCancel = true;
      } else {
        _isSlidingToCancel = false;
      }
    });
  }

  void _handleRecordSlideEnd(DragEndDetails details) {
    if (!_isRecording) return;

    if (_isSlidingToCancel) {
      _cancelRecording();
    } else if (!_isRecordingLocked) {
      // Si on relâche sans verrouiller, on envoie
      _stopRecording(send: true);
    }
  }

  // ==================== LECTURE AUDIO ====================
  Future<void> _playAudio(String messageId, String fileUrl) async {
    try {
      // Arrêter tous les autres lecteurs
      for (var entry in _audioPlayers.entries) {
        if (entry.key != messageId && entry.value.playing) {
          await entry.value.stop();
        }
      }

      // Créer ou récupérer le lecteur
      AudioPlayer? player = _audioPlayers[messageId];
      if (player == null) {
        player = AudioPlayer();
        _audioPlayers[messageId] = player;
        
        // Écouter les événements de fin
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            setState(() {});
          }
        });
      }

      // Charger et jouer
      if (player.playing) {
        await player.pause();
      } else {
        await player.setUrl(fileUrl);
        player.play();
      }
      
      setState(() {});
    } catch (e) {
      print('Erreur lecture audio: $e');
      _showError('Impossible de lire l\'audio');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  // ==================== LECTURE VIDEO ====================
  Future<void> _initializeVideoPlayer(String messageId, String videoUrl) async {
    try {
      if (_videoControllers.containsKey(messageId)) return;

      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await controller.initialize();

      final chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio,
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Icon(Icons.error, color: Colors.red, size: 50),
          );
        },
      );

      setState(() {
        _videoControllers[messageId] = controller;
        _chewieControllers[messageId] = chewieController;
      });
    } catch (e) {
      print('Erreur initialisation vidéo: $e');
    }
  }

  // ==================== UI ====================
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
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showOptionsMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.serviceName != null)
            _buildServiceInfoBanner(),
          Expanded(
            child: Consumer<MessageProvider>(
              builder: (context, provider, child) {
                final messages = provider.getMessages(widget.conversationId);
                
                if (provider.isLoading && messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppConstants.primaryRed),
                  );
                }

                if (messages.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildMessagesList(messages);
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle() {
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
            if (widget.otherUser.isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.otherUser.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_otherUserTyping)
                const Text(
                  'En train d\'écrire...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                )
              else if (widget.otherUser.isOnline)
                const Text(
                  'En ligne',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                )
              else if (widget.otherUser.lastSeen != null)
                Text(
                  'Vu ${_formatLastSeen(widget.otherUser.lastSeen!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLastSeen(DateTime date) {
    final now = DateTime.now();
    if (now.difference(date).inMinutes < 1) {
      return "à l'instant";
    } else if (now.difference(date).inMinutes < 60) {
      return "il y a ${now.difference(date).inMinutes} min";
    } else if (now.difference(date).inHours < 24) {
      return "il y a ${now.difference(date).inHours} h";
    } else {
      return DateFormat('dd/MM/yy HH:mm').format(date);
    }
  }

  Widget _buildServiceInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange[50],
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Conversation à propos de: ${widget.serviceName}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
              ),
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
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun message',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Envoyez votre premier message',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(List<MessageModel> messages) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final showDate = index == 0 || 
            messages[index].createdAt.day != messages[index - 1].createdAt.day;
        
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
    String dateText;
    
    if (now.difference(date).inDays == 0) {
      dateText = "Aujourd'hui";
    } else if (now.difference(date).inDays == 1) {
      dateText = 'Hier';
    } else {
      dateText = DateFormat('dd MMMM yyyy', 'fr_FR').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateText,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CircleAvatar(
        radius: 16,
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
                  fontSize: 12,
                  color: AppConstants.primaryRed,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildVideoPlayer(MessageModel message) {
    if (!_chewieControllers.containsKey(message.id)) {
      _initializeVideoPlayer(message.id, message.fileUrl!);
      return Container(
        height: 200,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Container(
      height: 200,
      child: Chewie(
        controller: _chewieControllers[message.id]!,
      ),
    );
  }

  Widget _buildAudioPlayer(MessageModel message) {
    final player = _audioPlayers[message.id];
    final isPlaying = player?.playing ?? false;
    final duration = player?.duration ?? Duration.zero;
    final position = player?.position ?? Duration.zero;

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppConstants.primaryRed,
                ),
                onPressed: () => _playAudio(message.id, message.fileUrl!),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: duration.inSeconds > 0 
                          ? position.inSeconds / duration.inSeconds 
                          : 0,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(AppConstants.primaryRed),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
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

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRecording) _buildWhatsAppRecordingIndicator(),
          Row(
            children: [
              // Bouton pour pièces jointes
              _buildAttachmentButton(),
              
              // Champ de texte
              Expanded(
                child: _buildTextField(),
              ),
              
              // Bouton d'envoi ou micro (style WhatsApp)
              _buildWhatsAppSendButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppRecordingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 60,
      child: GestureDetector(
        onHorizontalDragUpdate: _handleRecordSlideUpdate,
        onHorizontalDragEnd: _handleRecordSlideEnd,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            children: [
              // Animation de slide pour annuler
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _isSlidingToCancel ? 60 : 0,
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              
              Row(
                children: [
                  // Indicateur d'annulation
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isSlidingToCancel ? 60 : 0,
                    child: _isSlidingToCancel
                        ? const Center(
                            child: Icon(
                              Icons.close,
                              color: Colors.red,
                              size: 24,
                            ),
                          )
                        : null,
                  ),
                  
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatDuration(_recordDuration),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!_isRecordingLocked) ...[
                          const SizedBox(width: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '↔ glisser pour annuler',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // Bouton de verrouillage
                  if (!_isRecordingLocked)
                    GestureDetector(
                      onTap: _lockRecording,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock,
                          color: Colors.grey,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.attach_file, color: AppConstants.primaryRed),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) {
        switch (value) {
          case 'camera':
            _takePhoto();
            break;
          case 'image':
            _pickImage();
            break;
          case 'video':
            _pickVideo();
            break;
          case 'record_video':
            _recordVideo();
            break;
          case 'document':
            _pickDocument();
            break;
          case 'location':
            _sendLocation();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'camera',
          child: Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.blue),
              SizedBox(width: 8),
              Text('Prendre une photo'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'image',
          child: Row(
            children: [
              Icon(Icons.image, color: Colors.green),
              SizedBox(width: 8),
              Text('Choisir une image'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'video',
          child: Row(
            children: [
              Icon(Icons.video_library, color: Colors.purple),
              SizedBox(width: 8),
              Text('Choisir une vidéo'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'record_video',
          child: Row(
            children: [
              Icon(Icons.videocam, color: Colors.red),
              SizedBox(width: 8),
              Text('Enregistrer une vidéo'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'document',
          child: Row(
            children: [
              Icon(Icons.insert_drive_file, color: Colors.orange),
              SizedBox(width: 8),
              Text('Document'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'location',
          child: Row(
            children: [
              Icon(Icons.location_on, color: Colors.red),
              const SizedBox(width: 8),
              Text(_isSendingLocation ? 'Envoi en cours...' : 'Localisation'),
            ],
          ),
          enabled: !_isSendingLocation,
        ),
      ],
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search, color: AppConstants.primaryRed),
              title: const Text('Rechercher dans la conversation'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoon('Recherche');
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off, color: AppConstants.primaryRed),
              title: const Text('Désactiver les notifications'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoon('Notifications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('Bloquer', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showBlockConfirmation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Supprimer la conversation', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bloquer l\'utilisateur'),
        content: Text('Voulez-vous vraiment bloquer ${widget.otherUser.name} ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showComingSoon('Blocage');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la conversation'),
        content: const Text('Voulez-vous vraiment supprimer cette conversation ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Retour à la liste des conversations
              _showComingSoon('Suppression');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(imageUrl),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLocation(double lat, double lng) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final uri = Uri.parse(url);
    
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
    final extension = url.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _getFileSize(String? url) {
    // À implémenter avec la taille réelle du fichier
    return 'Fichier';
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Bientôt disponible'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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
    _slideAnimation.dispose();
    _audioRecorder.dispose();
    
    // Disposer tous les lecteurs audio
    for (var player in _audioPlayers.values) {
      player.dispose();
    }
    
    // Disposer tous les lecteurs vidéo
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    for (var controller in _chewieControllers.values) {
      controller.dispose();
    }
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}