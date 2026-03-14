import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/message_provider.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../utils/constants.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final _storage = const FlutterSecureStorage();
  
  bool _isTyping = false;
  Timer? _typingDebounce;
  bool _otherUserTyping = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages();
    _setupListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MessageProvider>().loadMessages(widget.conversationId);
    }
  }

  void _loadMessages() async {
    await context.read<MessageProvider>().loadMessages(widget.conversationId);
    await context.read<MessageProvider>().markConversationAsRead(widget.conversationId);
    _scrollToBottom();
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
    try {
      final token = await _storage.read(key: 'auth_token');
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/conversation/${widget.conversationId}/typing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_typing': isTyping}),
      );
    } catch (e) {
      print('Erreur envoi statut typing: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? content, String? filePath, String? type}) async {
    if ((content == null || content.isEmpty) && filePath == null) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      final messageType = type ?? (filePath != null ? _getFileType(filePath) : 'text');

      await context.read<MessageProvider>().sendMessage(
        widget.conversationId,
        type: messageType,
        content: content,
        filePath: filePath,
      );

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      _showError('Erreur lors de l\'envoi du message');
    } finally {
      setState(() => _isSending = false);
    }
  }

  String _getFileType(String path) {
    final extension = path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      return 'image';
    } else if (['mp4', 'mov', 'avi', 'mkv', '3gp'].contains(extension)) {
      return 'video';
    } else if (['mp3', 'm4a', 'aac', 'wav'].contains(extension)) {
      return 'audio';
    } else {
      return 'document';
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
        await _sendMessage(
          filePath: image.path,
          type: 'image',
        );
      }
    } catch (e) {
      _showError('Erreur lors de la sélection de l\'image');
    }
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
        title: Row(
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
                      'Vu ${DateFormat('HH:mm').format(widget.otherUser.lastSeen!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.serviceName != null)
            Container(
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
            ),
          
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
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
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

  Widget _buildMessageBubble(MessageModel message) {
    final isMe = message.isMe;
    final timeFormat = DateFormat('HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
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
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? AppConstants.primaryRed : Colors.white,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
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
                  if (message.content.isNotEmpty)
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
                          color: isMe ? Colors.white70 : Colors.grey[500],
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.readAt != null
                              ? Icons.done_all
                              : Icons.done,
                          size: 12,
                          color: message.readAt != null
                              ? Colors.blue[200]
                              : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[200],
              child: const Icon(
                Icons.person,
                size: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

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
      
      case 'document':
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.insert_drive_file, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.fileUrl?.split('/').last ?? 'Document',
                  style: TextStyle(
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      
      default:
        return const SizedBox.shrink();
    }
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
      child: Row(
        children: [
          // Bouton pour pièces jointes
          PopupMenuButton<String>(
            icon: const Icon(Icons.attach_file, color: AppConstants.primaryRed),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              switch (value) {
                case 'image':
                  _pickImage();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'image',
                child: Row(
                  children: [
                    Icon(Icons.image, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Image'),
                  ],
                ),
              ),
            ],
          ),

          // Champ de texte
          Expanded(
            child: Container(
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
                textInputAction: TextInputAction.send,
                onSubmitted: (value) => _sendMessage(content: value),
                enabled: !_isSending,
              ),
            ),
          ),

          // Bouton d'envoi
          if (_messageController.text.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: const BoxDecoration(
                color: AppConstants.primaryRed,
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
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}