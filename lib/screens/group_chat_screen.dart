import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/user_avatar.dart';
import 'call_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> members;

  GroupChatScreen({
    required this.groupId,
    required this.groupName,
    required this.members,
  });

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;
  String? _myProfilePhotoBase64;
  String? _myLegacyPhotoUrl;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    _loadMyPhoto();
  }

  Future<void> _loadMyPhoto() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!mounted) return;
      final d = doc.data();
      setState(() {
        _myProfilePhotoBase64 = d?['profilePhotoBase64'] as String?;
        _myLegacyPhotoUrl =
            d?['photoUrl'] as String? ?? _auth.currentUser?.photoURL;
      });
    } catch (_) {}
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      // Get all messages in this group that haven't been read by current user
      final messages = await _firestore
          .collection('chats')
          .doc(widget.groupId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUserId)
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
      print('Error marking messages as read: $e');
    }
  }

  Future<String> _getDecryptedMessage(String message, bool isEncrypted) async {
    try {
      if (!isEncrypted) {
        return message;
      }
      
      // Try fallback decryption first
      final result = await EncryptionService.decryptWithFallback(message, widget.groupId);
      
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

  Future<void> _startGroupCall({required bool isVideo}) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final others = widget.members.where((id) => id != currentUserId).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No other members are available to call.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selectedUserId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: others.length,
            itemBuilder: (context, index) {
              final uid = others[index];
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _firestore.collection('users').doc(uid).get(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  final name =
                      (data?['name'] as String?) ??
                      (data?['email'] as String?)?.split('@').first ??
                      'User';
                  final email = (data?['email'] as String?) ?? '';
                  return ListTile(
                    leading: UserAvatar(
                      name: name,
                      profilePhotoBase64: data?['profilePhotoBase64'] as String?,
                      photoUrl: data?['photoUrl'] as String?,
                      radius: 20,
                    ),
                    title: Text(name),
                    subtitle: email.isEmpty ? null : Text(email),
                    onTap: () => Navigator.of(context).pop(uid),
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (selectedUserId == null || !mounted) return;
    final userDoc = await _firestore.collection('users').doc(selectedUserId).get();
    final d = userDoc.data();
    final otherName =
        (d?['name'] as String?) ??
        (d?['email'] as String?)?.split('@').first ??
        'User';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen.outgoing(
          calleeId: selectedUserId,
          calleeName: otherName,
          isVideo: isVideo,
          otherPhotoUrl: d?['photoUrl'] as String?,
          otherPhotoBase64: d?['profilePhotoBase64'] as String?,
        ),
      ),
    );
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sending) return;

    setState(() => _sending = true);
    _messageController.clear();

    try {
      final participantIds = await EncryptionService.getChatParticipants(widget.groupId);
      if (participantIds.isEmpty) {
        participantIds.addAll(widget.members);
      }
      final sharedKey = await EncryptionService.getOrCreateSharedKey(
        widget.groupId,
        participantIds: participantIds,
      );
      await EncryptionService.storeSharedKey(widget.groupId, sharedKey, participantIds);
      final encryptedMessage = EncryptionService.encryptMessage(message, sharedKey);

      await _firestore
          .collection('chats')
          .doc(widget.groupId)
          .collection('messages')
          .add({
        'message': encryptedMessage,
        'senderId': _auth.currentUser?.uid,
        'senderName': _auth.currentUser?.displayName ?? _auth.currentUser?.email?.split('@')[0] ?? 'You',
        'senderPhotoBase64': _myProfilePhotoBase64,
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': [_auth.currentUser?.uid],
        'isRead': true,
        'isEncrypted': true,
      });

      await _firestore.collection('chats').doc(widget.groupId).update({
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

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppTheme.surfaceGray,
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const SizedBox(width: 8),
            const AppLogo(size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.groupName,
                    style: tt.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    '${widget.members.length} members',
                    style: tt.bodySmall?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
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
            icon: Icon(Icons.call, color: Colors.white),
            tooltip: 'Start call with a group member',
            onPressed: () => _startGroupCall(isVideo: false),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'info':
                  _showGroupInfo();
                  break;
                case 'members':
                  _showGroupMembers();
                  break;
                case 'leave':
                  _leaveGroup();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('Group Info'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'members',
                child: Row(
                  children: [
                    Icon(Icons.people),
                    SizedBox(width: 8),
                    Text('View Members'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Leave Group', style: TextStyle(color: Colors.red)),
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
                  .doc(widget.groupId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error loading messages'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Container(
                      padding: EdgeInsets.all(32),
                      margin: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                        boxShadow: AppTheme.softShadowLight(),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const AppLogo(size: 32),
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
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isEncrypted = data['isEncrypted'] ?? false;
                    final message = data['message'] ?? '';
                    final senderName = data['senderName'] ?? 'Unknown';
                    final timestamp = data['timestamp'] as Timestamp?;
                    final isMe = data['senderId'] == _auth.currentUser?.uid;

                    return FutureBuilder<String>(
                      future: _getDecryptedMessage(message, isEncrypted),
                      builder: (context, snapshot) {
                        final displayMessage = snapshot.data ?? message;
                        
                        return Container(
                          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                UserAvatar(
                                  name: senderName,
                                  profilePhotoBase64:
                                      data['senderPhotoBase64'] as String?,
                                  photoUrl: data['senderPhotoUrl'] as String?,
                                  radius: 14,
                                  backgroundColor: AppTheme.accentCyan.withOpacity(0.14),
                                  foregroundColor: AppTheme.accentCyan,
                                ),
                                SizedBox(width: 8),
                              ],
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                                  decoration: BoxDecoration(
                                    color: isMe ? AppTheme.primaryBlue : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(isMe ? 18 : 6),
                                      bottomRight: Radius.circular(isMe ? 6 : 18),
                                    ),
                                    border: isMe ? null : Border.all(color: AppTheme.lightGray),
                                    boxShadow: isMe
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
                                      if (!isMe)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            senderName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                              color: isMe ? Colors.white70 : AppTheme.mediumGray,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        displayMessage,
                                        style: TextStyle(
                                          color: isMe ? Colors.white : AppTheme.darkSlate,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          height: 1.25,
                                        ),
                                      ),
                                      if (timestamp != null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatTime(timestamp.toDate()),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isMe ? Colors.white70 : AppTheme.mediumGray,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (isMe) ...[
                                SizedBox(width: 8),
                                UserAvatar(
                                  name: _auth.currentUser?.displayName ??
                                      _auth.currentUser?.email?.split('@').first ??
                                      'You',
                                  profilePhotoBase64: _myProfilePhotoBase64,
                                  photoUrl: _myLegacyPhotoUrl,
                                  radius: 16,
                                  backgroundColor: AppTheme.primaryBlue,
                                  foregroundColor: Colors.white,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
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
                          color: AppTheme.accentCyan.withOpacity(0.12),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
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
                      color: _sending ? AppTheme.mediumGray : AppTheme.accentCyan,
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${dateTime.day}/${dateTime.month}';
    } else if (difference.inHours > 0) {
      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showGroupInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Group Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group: ${widget.groupName}'),
            SizedBox(height: 8),
            Text('Members: ${widget.members.length}'),
            SizedBox(height: 8),
            Text('🔒 All messages are encrypted'),
            SizedBox(height: 8),
            Text('Group ID: ${widget.groupId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGroupMembers() async {
    try {
      final membersData = <Map<String, dynamic>>[];
      
      for (String memberId in widget.members) {
        final userDoc = await _firestore.collection('users').doc(memberId).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          membersData.add({
            'uid': memberId,
            'name': userData['name'] ?? 'Unknown',
            'email': userData['email'] ?? '',
            'photoUrl': userData['photoUrl'],
            'profilePhotoBase64': userData['profilePhotoBase64'],
          });
        }
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Group Members'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: membersData.length,
              itemBuilder: (context, index) {
                final member = membersData[index];
                return ListTile(
                  leading: UserAvatar(
                    name: member['name'] as String? ?? '?',
                    profilePhotoBase64:
                        member['profilePhotoBase64'] as String?,
                    photoUrl: member['photoUrl'] as String?,
                    radius: 22,
                  ),
                  title: Text(member['name']),
                  subtitle: Text(member['email']),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('Error loading members: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading members'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _leaveGroup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave Group'),
        content: Text('Are you sure you want to leave "${widget.groupName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performLeaveGroup();
            },
            child: Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performLeaveGroup() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      // Remove user from group participants
      await _firestore.collection('chats').doc(widget.groupId).update({
        'participants': FieldValue.arrayRemove([currentUserId]),
      });

      // Add a system message about user leaving
      await _firestore
          .collection('chats')
          .doc(widget.groupId)
          .collection('messages')
          .add({
        'message': '${_auth.currentUser?.displayName ?? 'User'} left the group',
        'senderId': 'system',
        'senderName': 'System',
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': [],
        'isRead': false,
        'isEncrypted': false,
        'isSystemMessage': true,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Left group successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Error leaving group: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leaving group'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
