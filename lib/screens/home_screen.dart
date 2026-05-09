import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';
import 'admin_panel_screen.dart';
import 'login_screen.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';
import 'call_screen.dart';
import '../services/auth_service.dart';
import '../services/mfa_session_service.dart';
import '../services/audit_service.dart';
import '../services/call_service.dart';
import '../models/call_session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/user_avatar.dart';
import 'edit_profile_screen.dart';

int _compareCallDocumentsByTime(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  final ta = a.data()['createdAt'];
  final tb = b.data()['createdAt'];
  final da = ta is Timestamp ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
  final db = tb is Timestamp ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
  return db.compareTo(da);
}

String _formatCallDurationSeconds(int? sec) {
  if (sec == null || sec <= 0) return '';
  final m = sec ~/ 60;
  final s = sec % 60;
  if (m >= 60) {
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h}h ${mm}m';
  }
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isManager = false;
  bool _roleChecked = false;
  StreamSubscription<CallSession?>? _incomingCallSub;
  final Set<String> _shownIncomingCallIds = {};

  /// Stable streams so [StreamBuilder]s are not reset every chats-list rebuild (fixes avatar flicker).
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>> _userDocStreams = {};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>> _unreadMessageStreams = {};
  final Set<String> _chatOtherUserIdFixPending = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return _userDocStreams.putIfAbsent(
      uid,
      () => _firestore.collection('users').doc(uid).snapshots(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _unreadMessagesStream(String chatId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _unreadMessageStreams.putIfAbsent(
      chatId,
      () => _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: uid)
          .snapshots(),
    );
  }

  String? _chatPreviewText(dynamic lastMessage) {
    final raw = lastMessage?.toString().trim();
    if (raw == null || raw.isEmpty) return 'No messages yet';
    if (raw.toLowerCase() == '[encrypted message]'.toLowerCase()) return null;
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    _incomingCallSub = CallService.incomingCallsStream().listen((session) {
      if (session == null || _shownIncomingCallIds.contains(session.callId)) return;
      _shownIncomingCallIds.add(session.callId);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        String? callerPhoto;
        String? callerB64;
        if (session.callerId.isNotEmpty) {
          try {
            final doc =
                await _firestore.collection('users').doc(session.callerId).get();
            final d = doc.data();
            callerPhoto = d?['photoUrl'] as String?;
            callerB64 = d?['profilePhotoBase64'] as String?;
          } catch (_) {}
        }
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen.incoming(
              callId: session.callId,
              callerName: session.callerName,
              isVideo: session.isVideo,
              otherPhotoUrl: callerPhoto,
              otherPhotoBase64: callerB64,
            ),
          ),
        ).then((_) => _shownIncomingCallIds.remove(session.callId));
      });
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkUserRole() async {
    if (_roleChecked) return;
    _roleChecked = true;
    
    try {
      final isManager = await _authService.isUserManager().timeout(
        Duration(seconds: 3),
        onTimeout: () => false,
      );
      if (mounted) {
        setState(() {
          _isManager = isManager;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isManager = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text(
              'SECURELY',
              style: tt.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EditProfileScreen(),
                      ),
                    );
                    break;
                  case 'admin':
                    if (_isManager) {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => AdminPanelScreen(),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            return SlideTransition(
                              position: animation.drive(
                                Tween(begin: Offset(1.0, 0.0), end: Offset.zero)
                                    .chain(CurveTween(curve: AppTheme.smoothCurve)),
                              ),
                              child: child,
                            );
                          },
                        ),
                      );
                    }
                    break;
                  case 'logout':
                    _signOut();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, color: AppTheme.primaryBlue),
                      SizedBox(width: 8),
                      Text('Profile'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: AppTheme.errorRed),
                      SizedBox(width: 8),
                      Text('Logout'),
                    ],
                  ),
                ),
                if (_isManager)
                  PopupMenuItem(
                    value: 'admin',
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings, color: AppTheme.successGreen),
                        SizedBox(width: 8),
                        Text('Admin Panel'),
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
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Material(
                color: Colors.white,
                elevation: 0,
                shadowColor: Colors.black12,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                  side: BorderSide(color: AppTheme.lightGray.withValues(alpha: 0.7)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: tt.bodyLarge?.copyWith(color: AppTheme.darkSlate),
                  decoration: InputDecoration(
                    hintText: 'Search users or groups…',
                    hintStyle: TextStyle(color: AppTheme.mediumGray, fontSize: 15),
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AppTheme.mediumGray, size: 22),
                    suffixIcon: _isSearching
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: AppTheme.mediumGray),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _isSearching = false;
                                _searchResults = [];
                              });
                            },
                          )
                        : null,
                    filled: false,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  ),
                  onChanged: _searchUsers,
                  onSubmitted: (value) {
                    if (value.trim().isEmpty) {
                      _searchController.clear();
                    }
                  },
                ),
              ),
            ),
            
            Expanded(
              child: _isSearching ? _buildSearchResults() : _buildMainContent(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGroup,
        backgroundColor: AppTheme.accentCyan,
        elevation: 2,
        child: Icon(Icons.group_add, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Container(
          padding: EdgeInsets.all(32),
          margin: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: AppTheme.primaryBlue.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: AppTheme.cardShadow,
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
                child: Icon(Icons.search_off, size: 32, color: Colors.white),
              ),
              SizedBox(height: 16),
              Text(
                'No users found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkSlate,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Try searching for a different name',
                style: TextStyle(
                  color: AppTheme.mediumGray,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty && _searchController.text.isEmpty) {
      return Center(
        child: Container(
          padding: EdgeInsets.all(32),
          margin: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: AppTheme.primaryBlue.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: AppTheme.cardShadow,
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
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Loading users...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkSlate,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final user = _searchResults[index];
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: ListTile(
                  onTap: () => _startChat(user),
                  leading: UserAvatar(
                    name: user['name'] ?? user['email']?.split('@')[0] ?? 'User',
                    profilePhotoBase64: user['profilePhotoBase64'] as String?,
                    photoUrl: user['photoUrl'] as String?,
                    radius: 22,
                  ),
                  title: Text(
                    user['name'] ?? user['email']?.split('@')[0] ?? 'Unknown User',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                  subtitle: Text(
                    user['email'],
                    style: TextStyle(
                      color: AppTheme.mediumGray,
                    ),
                  ),
                  trailing: Icon(Icons.chat, color: AppTheme.accentCyan, size: 22),
                ),
              );
            },
          );
  }

      Widget _buildChatList() {
        final String? currentUid = _auth.currentUser?.uid;
        if (currentUid == null) {
          return Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('chats')
              .where('participants', arrayContains: currentUid)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

            final allChats = snapshot.data?.docs.toList() ?? [];
            
            final chats = allChats.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['type'] != 'group';
            }).toList();

            chats.sort((a, b) {
              final Map<String, dynamic> aData = a.data() as Map<String, dynamic>;
              final Map<String, dynamic> bData = b.data() as Map<String, dynamic>;
              final aTs = aData['lastMessageTime'];
              final bTs = bData['lastMessageTime'];
              final aMillis = (aTs is Timestamp) ? aTs.millisecondsSinceEpoch : 0;
              final bMillis = (bTs is Timestamp) ? bTs.millisecondsSinceEpoch : 0;
              return bMillis.compareTo(aMillis);
            });

        if (chats.isEmpty) {
          return _buildAllUsersList();
        }

        return ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index].data() as Map<String, dynamic>;
            return _buildChatTile(chat, chats[index].id);
          },
        );
      },
    );
  }

      Widget _buildChatTile(Map<String, dynamic> chat, String chatId) {
        final String? otherUserId = chat['otherUserId'];
        
        final participants = List<String>.from(chat['participants'] ?? []);
        final currentUserId = _auth.currentUser?.uid;
        final correctOtherUserId = participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => otherUserId ?? '',
        );
        
        if (correctOtherUserId != otherUserId && correctOtherUserId.isNotEmpty) {
          if (!_chatOtherUserIdFixPending.contains(chatId)) {
            _chatOtherUserIdFixPending.add(chatId);
            _firestore.collection('chats').doc(chatId).update({
              'otherUserId': correctOtherUserId,
            }).whenComplete(() {
              if (mounted) _chatOtherUserIdFixPending.remove(chatId);
            });
          }
        }
        
        if (correctOtherUserId.isEmpty) {
          return SizedBox.shrink();
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userDocStream(correctOtherUserId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return ListTile(
                leading: CircularProgressIndicator(),
                title: Text('Loading...'),
              );
            }
            if (snapshot.hasError) {
              return SizedBox.shrink();
            }

            final userData = snapshot.data?.data();
            if (userData == null) return SizedBox.shrink();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _unreadMessagesStream(chatId),
              builder: (context, unreadSnapshot) {
                bool hasUnreadMessages = false;
                if (unreadSnapshot.hasData) {
                  for (var doc in unreadSnapshot.data!.docs) {
                    final data = doc.data();
                    final readBy = List<String>.from(data['readBy'] ?? []);
                    if (!readBy.contains(_auth.currentUser?.uid)) {
                      hasUnreadMessages = true;
                      break;
                    }
                  }
                }

                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasUnreadMessages ? AppTheme.primaryBlue.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: hasUnreadMessages 
                      ? Border.all(color: AppTheme.primaryBlue.withOpacity(0.3), width: 1)
                      : Border.all(color: AppTheme.primaryBlue.withOpacity(0.1), width: 1),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    minVerticalPadding: 12,
                    leading: Stack(
                      children: [
                        UserAvatar(
                          name: userData['name'] ??
                              userData['email']?.split('@')[0] ??
                              'User',
                          profilePhotoBase64:
                              userData['profilePhotoBase64'] as String?,
                          photoUrl: userData['photoUrl'] as String?,
                          radius: 22,
                        ),
                        if (hasUnreadMessages)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            userData['name'] ?? userData['email']?.split('@')[0] ?? 'Unknown User',
                            style: TextStyle(
                              fontWeight: hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
                              color: AppTheme.darkSlate,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (hasUnreadMessages)
                          Icon(
                            Icons.circle,
                            color: Colors.blue,
                            size: 8,
                          ),
                      ],
                    ),
                    subtitle: _chatPreviewText(chat['lastMessage']) == null
                        ? null
                        : Text(
                            _chatPreviewText(chat['lastMessage'])!,
                            style: TextStyle(
                              fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
                              color: hasUnreadMessages ? AppTheme.primaryBlue : AppTheme.mediumGray,
                              fontSize: 14,
                            ),
                          ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            chatId: chatId,
                            otherUser: {
                              'uid': correctOtherUserId,
                              ...userData,
                            },
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
  }

  void _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final allUsers = await _firestore.collection('users').get();
      final results = <Map<String, dynamic>>[];
      final currentUserId = _auth.currentUser?.uid;
      
      for (var doc in allUsers.docs) {
        if (doc.id == currentUserId) {
          continue;
        }
        
        final userData = doc.data();
        
        final name = userData['name']?.toString().toLowerCase() ?? '';
        final email = userData['email']?.toString().toLowerCase() ?? '';
        final searchQuery = query.toLowerCase();
        
        if (name.contains(searchQuery) || email.contains(searchQuery)) {
          results.add({
            'uid': doc.id,
            ...userData,
          });
        }
      }
      
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
      });
    }
  }

  void _startChat(Map<String, dynamic> user) async {
    try {
      final existingChat = await _firestore
          .collection('chats')
          .where('participants', arrayContains: _auth.currentUser?.uid)
          .get();

      String chatId = '';
      for (var doc in existingChat.docs) {
        final data = doc.data();
        if (data['participants'].contains(user['uid'])) {
          chatId = doc.id;
          break;
        }
      }

      if (chatId.isEmpty) {
        final chatData = {
          'participants': [_auth.currentUser?.uid, user['uid']],
          'lastMessage': null,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'otherUserId': user['uid'],
        };
        final docRef = await _firestore.collection('chats').add(chatData);
        chatId = docRef.id;
      } else {
        await _firestore.collection('chats').doc(chatId).update({
          'otherUserId': user['uid'],
        });
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chatId: chatId,
            otherUser: user,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start chat'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildAllUsersList() {
    return FutureBuilder<QuerySnapshot>(
      future: _firestore.collection('users').get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading users...'),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text('Error loading users'),
                SizedBox(height: 8),
                Text('${snapshot.error}'),
              ],
            ),
          );
        }

        final users = snapshot.data?.docs ?? [];
        final currentUserId = _auth.currentUser?.uid;
        
        final otherUsers = users.where((doc) => doc.id != currentUserId).toList();

        if (otherUsers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No other users found', style: TextStyle(fontSize: 18, color: Colors.grey)),
                SizedBox(height: 8),
                Text('Register another account to start chatting'),
                SizedBox(height: 4),
                Text('🔒 All messages are encrypted', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          );
        }

        return ListView.builder(
                itemCount: otherUsers.length,
                itemBuilder: (context, index) {
                  final user = otherUsers[index].data() as Map<String, dynamic>;
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      onTap: () {
                        final userToPass = {
                          'uid': otherUsers[index].id,
                          ...user,
                        };
                        _startChat(userToPass);
                      },
                      leading: UserAvatar(
                        name: user['name'] ??
                            user['email']?.split('@')[0] ??
                            'User',
                        profilePhotoBase64:
                            user['profilePhotoBase64'] as String?,
                        photoUrl: user['photoUrl'] as String?,
                        radius: 22,
                      ),
                      title: Text(
                        user['name'] ?? user['email']?.split('@')[0] ?? 'Unknown User',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(user['email']),
                      trailing: Icon(Icons.chat, color: Colors.green),
                    ),
                  );
                },
              );
      },
    );
  }

  void _signOut() async {
    final user = _authService.currentUser;
    await AuditService.logLogout(userId: user?.uid, email: user?.email);
    await MFASessionService.clearMFASession();

    await _authService.signOut();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildMainContent() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
              boxShadow: AppTheme.cardShadow,
            ),
            child: TabBar(
              indicator: BoxDecoration(
                color: AppTheme.primaryBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.mediumGray,
              labelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat, size: 18),
                      SizedBox(width: 6),
                      Text('Chats'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group, size: 18),
                      SizedBox(width: 6),
                      Text('Groups'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call, size: 18),
                      SizedBox(width: 6),
                      Text('Calls'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildChatList(),
                _buildGroupList(),
                _buildCallHistoryList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList() {
    final String? currentUid = _auth.currentUser?.uid;
    if (currentUid == null) {
      return Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chats')
          .where('type', isEqualTo: 'group')
          .where('participants', arrayContains: currentUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final groups = snapshot.data?.docs.toList() ?? [];

        if (groups.isEmpty) {
          return Center(
            child: Container(
              padding: EdgeInsets.all(32),
              margin: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(
                  color: AppTheme.accentCyan.withOpacity(0.15),
                  width: 1,
                ),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.group, size: 32, color: Colors.white),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No groups yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Create a group to start chatting!',
                    style: TextStyle(
                      color: AppTheme.mediumGray,
                    ),
                  ),
                  SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue,
                      borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _createGroup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      icon: Icon(Icons.group_add, color: Colors.white),
                      label: Text(
                        'Create Group',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index].data() as Map<String, dynamic>;
            return _buildGroupTile(group, groups[index].id);
          },
        );
      },
    );
  }

  String _callHistoryStatusLine({
    required bool isCaller,
    required String callStatus,
    required bool hadConnection,
    required int? durationSeconds,
    required bool isDeclined,
  }) {
    if (isDeclined) {
      return isCaller ? 'They declined' : 'You declined';
    }
    if (callStatus == 'ringing' || callStatus == 'connected') {
      return isCaller ? 'Outgoing · In progress' : 'Incoming · In progress';
    }
    if (callStatus == 'ended') {
      if (hadConnection) {
        if (durationSeconds != null && durationSeconds > 0) {
          final dur = _formatCallDurationSeconds(durationSeconds);
          if (dur.isNotEmpty) {
            return isCaller ? 'Outgoing · $dur' : 'Incoming · $dur';
          }
        }
        return isCaller ? 'Outgoing · Answered' : 'Incoming · Answered';
      }
      return isCaller ? 'No answer' : 'Missed call';
    }
    return callStatus;
  }

  Future<void> _openChatFromCallUser({
    required String otherUserId,
    required String fallbackName,
    String fallbackEmail = '',
  }) async {
    if (otherUserId.isEmpty) return;
    try {
      final doc = await _firestore.collection('users').doc(otherUserId).get();
      if (!mounted) return;
      final user = <String, dynamic>{
        'uid': otherUserId,
        if (doc.exists) ...doc.data()!,
        if (!doc.exists) 'name': fallbackName,
        if (!doc.exists) 'email': fallbackEmail,
      };
      _startChat(user);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open chat'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCallHistoryList() {
    final String? currentUid = _auth.currentUser?.uid;
    if (currentUid == null) {
      return Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('calls')
          .where('participants', arrayContains: currentUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
                  SizedBox(height: 12),
                  Text(
                    'Could not load call history',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkSlate,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(color: AppTheme.mediumGray, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final rawDocs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(rawDocs)
          ..sort(_compareCallDocumentsByTime);

        if (docs.isEmpty) {
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
                    child: Icon(Icons.call, size: 32, color: Colors.white),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No calls yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a voice or video call from any chat.',
                    style: TextStyle(
                      color: AppTheme.mediumGray,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(bottom: 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final docSnap = docs[index];
            final data = docSnap.data();
            final isCaller = data['callerId'] == currentUid;
            final callStatus = data['status'] as String? ?? '';
            final isDeclined = callStatus == 'declined';
            final isOngoing = callStatus == 'ringing' || callStatus == 'connected';
            final hadConnection = data['connectedAt'] != null;
            final durationSeconds = (data['durationSeconds'] as num?)?.toInt();
            final isVideo = (data['type'] as String? ?? 'audio') == 'video';

            final otherUserId = isCaller
                ? data['calleeId'] as String?
                : data['callerId'] as String?;
            final createdAt = data['createdAt'];
            final fallbackName = isCaller
                ? (data['calleeName'] as String? ?? 'Unknown')
                : (data['callerName'] as String? ?? 'Unknown');

            final icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
            Color iconColor;
            if (isOngoing) {
              iconColor = AppTheme.accentCyan;
            } else if (isDeclined || (!hadConnection && callStatus == 'ended' && !isCaller)) {
              iconColor = AppTheme.errorRed;
            } else if (!hadConnection && callStatus == 'ended' && isCaller) {
              iconColor = AppTheme.warningOrange;
            } else {
              iconColor = AppTheme.successGreen;
            }

            final statusLine = _callHistoryStatusLine(
              isCaller: isCaller,
              callStatus: callStatus,
              hadConnection: hadConnection,
              durationSeconds: durationSeconds,
              isDeclined: isDeclined,
            );

            String timeLabel = '';
            if (createdAt is Timestamp) {
              final dt = createdAt.toDate();
              timeLabel =
                  '${dt.month}/${dt.day}/${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            }

            Widget rowTile({
              required String name,
              required String email,
              required String? rowPhoto,
              required String? rowB64,
            }) {
              final subtitle = email.isNotEmpty
                  ? '$statusLine\n$timeLabel\n$email'
                  : '$statusLine\n$timeLabel';
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  boxShadow: AppTheme.softShadowLight(),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  minVerticalPadding: 12,
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        name: name,
                        profilePhotoBase64: rowB64,
                        photoUrl: rowPhoto,
                        radius: 22,
                        backgroundColor: iconColor.withValues(alpha: 0.15),
                        foregroundColor: iconColor,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: iconColor,
                          child: Icon(icon, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: TextStyle(
                      color: AppTheme.mediumGray,
                      height: 1.35,
                    ),
                  ),
                  isThreeLine: email.isNotEmpty,
                  onTap: otherUserId != null && otherUserId.isNotEmpty
                      ? () {
                          unawaited(_openChatFromCallUser(
                            otherUserId: otherUserId,
                            fallbackName: name,
                            fallbackEmail: email,
                          ));
                        }
                      : null,
                ),
              );
            }

            if (otherUserId == null || otherUserId.isEmpty) {
              return rowTile(
                name: fallbackName,
                email: '',
                rowPhoto: null,
                rowB64: null,
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userDocStream(otherUserId),
              builder: (context, userSnap) {
                String name = fallbackName;
                String email = '';
                String? rowPhoto;
                String? rowB64;

                final snap = userSnap.data;
                if (snap != null && snap.exists) {
                  final u = snap.data();
                  if (u != null) {
                    name = (u['name'] as String?) ?? name;
                    email = (u['email'] as String?) ?? '';
                    rowPhoto = u['photoUrl'] as String?;
                    rowB64 = u['profilePhotoBase64'] as String?;
                  }
                }

                return rowTile(
                  name: name,
                  email: email,
                  rowPhoto: rowPhoto,
                  rowB64: rowB64,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group, String groupId) {
    final groupName = group['groupName'] ?? 'Unknown Group';
    final participants = List<String>.from(group['participants'] ?? []);
    
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _unreadMessagesStream(groupId),
      builder: (context, unreadSnapshot) {
        bool hasUnreadMessages = false;
        if (unreadSnapshot.hasData) {
          for (var doc in unreadSnapshot.data!.docs) {
            final data = doc.data();
            final readBy = List<String>.from(data['readBy'] ?? []);
            if (!readBy.contains(_auth.currentUser?.uid)) {
              hasUnreadMessages = true;
              break;
            }
          }
        }
        
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: hasUnreadMessages ? AppTheme.accentCyan.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: hasUnreadMessages 
              ? Border.all(color: AppTheme.accentCyan.withOpacity(0.4), width: 1)
              : Border.all(color: AppTheme.lightGray, width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minVerticalPadding: 12,
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.accentCyan,
                  child: Icon(Icons.group, color: Colors.white, size: 20),
                ),
                if (hasUnreadMessages)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    groupName,
                    style: TextStyle(
                      fontWeight: hasUnreadMessages ? FontWeight.bold : FontWeight.normal,
                      color: AppTheme.darkSlate,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (hasUnreadMessages)
                  Icon(
                    Icons.circle,
                    color: Colors.blue,
                    size: 8,
                  ),
              ],
            ),
            subtitle: _chatPreviewText(group['lastMessage']) == null
                ? Text(
                    '${participants.length} members',
                    style: TextStyle(
                      fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
                      color: hasUnreadMessages ? AppTheme.accentCyan : AppTheme.mediumGray,
                      fontSize: 14,
                    ),
                  )
                : Text(
                    '${participants.length} members • ${_chatPreviewText(group['lastMessage'])}',
                    style: TextStyle(
                      fontWeight: hasUnreadMessages ? FontWeight.w500 : FontWeight.normal,
                      color: hasUnreadMessages ? AppTheme.accentCyan : AppTheme.mediumGray,
                      fontSize: 14,
                    ),
                  ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupChatScreen(
                    groupId: groupId,
                    groupName: groupName,
                    members: participants,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _createGroup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateGroupScreen()),
    );
    
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
