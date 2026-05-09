import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';
import '../services/report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> otherUser;

  ChatScreen({required this.chatId, required this.otherUser});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;
  String? _myProfilePhotoBase64;
  String? _myLegacyPhotoUrl;
  final Map<String, String> _decryptedMessageCache = {};
  final Map<String, Future<String>> _decryptFutures = {};

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    _loadMyProfilePhotos();
  }

  Future<void> _loadMyProfilePhotos() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!mounted) return;
      final d = doc.data();
      setState(() {
        _myProfilePhotoBase64 = d?['profilePhotoBase64'] as String?;
        _myLegacyPhotoUrl = d?['photoUrl'] as String? ?? _auth.currentUser?.photoURL;
      });
    } catch (_) {}
  }

  Future<String?> _getOtherUserId() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return null;
    final chat = await _firestore.collection('chats').doc(widget.chatId).get();
    final participants = List<String>.from(chat.data()?['participants'] ?? []);
    final other = participants.where((id) => id != currentUserId).toList();
    return other.isEmpty ? null : other.first;
  }

  void _startCall({required bool isVideo}) async {
    final otherUserId = await _getOtherUserId();
    if (otherUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start call.'),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final otherName = widget.otherUser['name'] as String? ?? widget.otherUser['email'] as String? ?? 'User';
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen.outgoing(
          calleeId: otherUserId,
          calleeName: otherName,
          isVideo: isVideo,
          otherPhotoUrl: widget.otherUser['photoUrl'] as String?,
          otherPhotoBase64: widget.otherUser['profilePhotoBase64'] as String?,
        ),
      ),
    );
  }

  Future<void> _showReportUserDialog() async {
    final reportedUserId = await _getOtherUserId();
    if (!mounted) return;
    if (reportedUserId == null || reportedUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not identify user to report.'),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reasons = <String>[
      'Harassment or hate speech',
      'Spam',
      'Impersonation',
      'Inappropriate content',
      'Other',
    ];

    String selectedReason = reasons.first;
    final detailsController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final baseTheme = Theme.of(context);
        bool showDetailsError = false;
        return Theme(
          data: baseTheme.copyWith(
            canvasColor: Colors.white,
            dividerColor: AppTheme.lightGray,
            dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: AppTheme.surfaceGray,
              hintStyle: TextStyle(color: AppTheme.mediumGray),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.lightGray),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.lightGray),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.6), width: 1.2),
              ),
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.flag_outlined, color: AppTheme.errorRed, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Report ${widget.otherUser['name'] ?? 'user'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppTheme.mediumGray,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  icon: const Icon(Icons.expand_more),
                  iconEnabledColor: AppTheme.mediumGray,
                  style: const TextStyle(
                    color: AppTheme.darkSlate,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  items: reasons
                      .map(
                        (r) => DropdownMenuItem<String>(
                          value: r,
                          child: Text(
                            r,
                            style: const TextStyle(
                              color: AppTheme.darkSlate,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    selectedReason = v;
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppTheme.mediumGray,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  maxLines: 4,
                  style: const TextStyle(color: AppTheme.darkSlate, fontSize: 14),
                  onChanged: (_) {
                    if (!showDetailsError) return;
                    if (detailsController.text.trim().isNotEmpty) {
                      setLocalState(() => showDetailsError = false);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Describe what happened (required).',
                    errorText: showDetailsError ? 'Please add details before submitting.' : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reports are reviewed by managers. Don’t include passwords or sensitive secrets.',
                  style: TextStyle(fontSize: 11, color: AppTheme.mediumGray, height: 1.2),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.mediumGray,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final details = detailsController.text.trim();
                  if (details.isEmpty) {
                    setLocalState(() => showDetailsError = true);
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit'),
              ),
            ],
          );
            },
          ),
        );
      },
    );

    final details = detailsController.text.trim();
    detailsController.dispose();
    if (submitted != true) return;

    try {
      final reportedEmail = widget.otherUser['email'] as String? ?? '';
      await ReportService.submitUserReport(
        reportedUserId: reportedUserId,
        reportedEmail: reportedEmail,
        reason: selectedReason,
        details: details,
        chatId: widget.chatId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report submitted. A manager will review it.'),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not submit report. Please try again.'),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      // Get all messages in this chat that haven't been read by current user
      final messages = await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUserId) // Only messages from others
          .get();

      // Mark each message as read by current user
      for (var doc in messages.docs) {
        final data = doc.data();
        final readBy = List<String>.from(data['readBy'] ?? []);
        
        if (!readBy.contains(currentUserId)) {
          readBy.add(currentUserId);
          await doc.reference.update({
            'readBy': readBy,
            'isRead': true,
          });
        }
      }
      
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 4),
            UserAvatar(
              name: widget.otherUser['name'] as String? ?? 'Chat',
              profilePhotoBase64:
                  widget.otherUser['profilePhotoBase64'] as String?,
              photoUrl: widget.otherUser['photoUrl'] as String?,
              radius: 22,
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.otherUser['name'] ?? 'Chat',
                    style: tt.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.call, color: Colors.white, size: 24),
            tooltip: 'Voice call',
            onPressed: () => _startCall(isVideo: false),
          ),
          IconButton(
            icon: Icon(Icons.videocam, color: Colors.white, size: 26),
            tooltip: 'Video call',
            onPressed: () => _startCall(isVideo: true),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white, size: 24),
            onSelected: (value) {
              if (value == 'report') {
                _showReportUserDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, color: AppTheme.errorRed),
                    SizedBox(width: 8),
                    Text('Report user'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        color: AppTheme.surfaceGray,
        child: Column(
          children: [
            // Messages list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Container(
                      padding: EdgeInsets.all(32),
                      margin: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                        border: Border.all(color: AppTheme.lightGray, width: 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UserAvatar(
                            name: widget.otherUser['name'] ?? 'Chat',
                            profilePhotoBase64:
                                widget.otherUser['profilePhotoBase64'] as String?,
                            photoUrl: widget.otherUser['photoUrl'] as String?,
                            radius: 32,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkSlate,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start the conversation!',
                            style: TextStyle(
                              color: AppTheme.mediumGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final doc = messages[index];
                    final message = doc.data() as Map<String, dynamic>;
                    final isCurrentUser = message['senderId'] == _auth.currentUser?.uid;
                    return _buildMessageBubble(
                      message,
                      isCurrentUser,
                      messageId: doc.id,
                      key: ValueKey(doc.id),
                    );
                  },
                );
              },
            ),
          ),

            // Message input
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.cardRadius),
                  topRight: Radius.circular(AppTheme.cardRadius),
                ),
                border: Border.all(color: AppTheme.lightGray, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.lightGray,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.12),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: TextStyle(
                          color: AppTheme.darkSlate,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: TextStyle(color: AppTheme.mediumGray),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          filled: true,
                          fillColor: Colors.transparent,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: _sending ? AppTheme.mediumGray : AppTheme.primaryBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: FloatingActionButton(
                      onPressed: _sending ? null : () => _sendMessage(),
                      mini: true,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      child: _sending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isCurrentUser, {
    required String messageId,
    Key? key,
  }) {
    final bubbleBg = isCurrentUser ? AppTheme.primaryBlue : Colors.white;
    final textColor = isCurrentUser ? Colors.white : AppTheme.darkSlate;
    final metaColor = isCurrentUser ? Colors.white70 : AppTheme.mediumGray;
    final encryptedRaw = (message['message'] ?? '') as String;
    final isEncrypted = message['isEncrypted'] ?? false;
    final cacheKey = '$messageId|${encryptedRaw.hashCode}|$isEncrypted';
    final cachedText = _decryptedMessageCache[cacheKey];
    final decryptFuture = _decryptFutures.putIfAbsent(
      cacheKey,
      () => _getDecryptedMessage(encryptedRaw, isEncrypted),
    );

    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[
            UserAvatar(
              name: (message['senderName'] ?? widget.otherUser['name'] ?? 'U')
                  .toString(),
              profilePhotoBase64:
                  widget.otherUser['profilePhotoBase64'] as String?,
              photoUrl: widget.otherUser['photoUrl'] as String?,
              radius: 14,
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
              foregroundColor: AppTheme.primaryBlue,
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isCurrentUser ? 18 : 6),
                  bottomRight: Radius.circular(isCurrentUser ? 6 : 18),
                ),
                border: isCurrentUser
                    ? null
                    : Border.all(color: AppTheme.lightGray),
                boxShadow: isCurrentUser
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryBlue.withOpacity(0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cachedText != null)
                    Text(
                      cachedText,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    )
                  else
                    FutureBuilder<String>(
                      future: decryptFuture,
                      builder: (context, snapshot) {
                        final value = snapshot.data;
                        if (value != null &&
                            _decryptedMessageCache[cacheKey] != value) {
                          _decryptedMessageCache[cacheKey] = value;
                        }
                        final content =
                            value ?? (isEncrypted ? 'Decrypting…' : encryptedRaw);
                        final isPlaceholder = value == null && isEncrypted;
                        return Text(
                          isPlaceholder ? '████████████' : content,
                          style: TextStyle(
                            color: isPlaceholder
                                ? Colors.transparent
                                : (value == null
                                    ? textColor.withOpacity(0.7)
                                    : textColor),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(message['timestamp']),
                        style: TextStyle(
                          fontSize: 11,
                          color: metaColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            UserAvatar(
              name: _auth.currentUser?.displayName ??
                  _auth.currentUser?.email?.split('@').first ??
                  'You',
              profilePhotoBase64: _myProfilePhotoBase64,
              photoUrl: _myLegacyPhotoUrl,
              radius: 14,
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
            ),
          ],
        ],
      ),
    );
  }

  Future<String> _getDecryptedMessage(String message, bool isEncrypted) async {
    try {
      if (!isEncrypted) {
        return message; // Message is not encrypted, return as-is
      }
      
      // Try fallback decryption first
      final result = await EncryptionService.decryptWithFallback(message, widget.chatId);
      
      // If fallback failed and it's still encrypted, handle as legacy message
      if (result.contains('[Encrypted message - key not available]')) {
        return EncryptionService.handleLegacyMessage(message, isEncrypted);
      }
      
      return result;
    } catch (e) {
      print('Decryption error: $e');
      return EncryptionService.handleLegacyMessage(message, isEncrypted);
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sending) return;

    setState(() => _sending = true);
    _messageController.clear();

    try {
      final participantIds = await EncryptionService.getChatParticipants(widget.chatId);
      if (participantIds.isEmpty) {
        final other = await _getOtherUserId();
        if (_auth.currentUser?.uid != null) {
          participantIds.add(_auth.currentUser!.uid);
        }
        if (other != null && other.isNotEmpty && !participantIds.contains(other)) {
          participantIds.add(other);
        }
      }
      final sharedKey = await EncryptionService.getOrCreateSharedKey(
        widget.chatId,
        participantIds: participantIds,
      );
      await EncryptionService.storeSharedKey(widget.chatId, sharedKey, participantIds);
      final encryptedMessage = EncryptionService.encryptMessage(message, sharedKey);

      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'message': encryptedMessage,
        'senderId': _auth.currentUser?.uid,
        'senderName': _auth.currentUser?.displayName ?? _auth.currentUser?.email?.split('@')[0] ?? 'You',
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': [_auth.currentUser?.uid],
        'isRead': true,
        'isEncrypted': true,
      });

      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': '[Encrypted Message]',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        _messageController.text = message;
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn\'t send. Check your connection and try again.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _sending = false);
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    
    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else {
      dateTime = DateTime.now();
    }
    
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
