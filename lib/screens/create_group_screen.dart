import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_chat.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/user_avatar.dart';

class CreateGroupScreen extends StatefulWidget {
  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _selectedMembers = [];
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      final usersSnapshot = await _firestore.collection('users').get();
      final users = usersSnapshot.docs
          .where((doc) => doc.id != currentUserId)
          .map((doc) => {
                'uid': doc.id,
                'name': doc.data()['name'] ?? 'Unknown',
                'email': doc.data()['email'] ?? '',
                'photoUrl': doc.data()['photoUrl'],
                'profilePhotoBase64': doc.data()['profilePhotoBase64'],
              })
          .toList();

      setState(() {
        _allUsers = users;
        _searchResults = users;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _searchUsers(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = _allUsers;
      });
      return;
    }

    final filtered = _allUsers.where((user) {
      final name = user['name'].toString().toLowerCase();
      final email = user['email'].toString().toLowerCase();
      final searchQuery = query.toLowerCase();
      return name.contains(searchQuery) || email.contains(searchQuery);
    }).toList();

    setState(() {
      _searchResults = filtered;
    });
  }

  void _toggleUserSelection(Map<String, dynamic> user) {
    setState(() {
      if (_selectedMembers.any((member) => member['uid'] == user['uid'])) {
        _selectedMembers.removeWhere((member) => member['uid'] == user['uid']);
      } else {
        _selectedMembers.add(user);
      }
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add at least one member to the group.'),
          backgroundColor: AppTheme.warningOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      // Add current user to members
      final allMembers = <String>[currentUserId, ..._selectedMembers.map((m) => m['uid'] as String)];

      final groupId = _firestore.collection('groups').doc().id;
      
      final group = GroupChat(
        id: groupId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        createdBy: currentUserId,
        members: allMembers,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('groups').doc(groupId).set(group.toMap());

      // Create group chat document
      await _firestore.collection('chats').doc(groupId).set({
        'type': 'group',
        'groupId': groupId,
        'groupName': group.name,
        'participants': allMembers,
        'createdBy': currentUserId,
        'createdAt': DateTime.now(),
        'lastMessage': null,
        'lastMessageTime': null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Group created!'),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      Navigator.pop(context, groupId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn\'t create group. Check your connection and try again.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() {
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppTheme.surfaceGray,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const AppLogo(size: 22),
            const SizedBox(width: 10),
            Text(
              'Create Group',
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
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppTheme.surfaceGray,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                    // Group details
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                        boxShadow: AppTheme.softShadowLight(),
                      ),
                      child: TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Group Name',
                          labelStyle: TextStyle(color: AppTheme.primaryBlue),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                            borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter group name';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                        boxShadow: AppTheme.softShadowLight(),
                      ),
                      child: TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          labelStyle: TextStyle(color: AppTheme.primaryBlue),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                            borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        maxLines: 2,
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // Selected members
                    if (_selectedMembers.isNotEmpty) ...[
                      Text(
                        'Selected Members (${_selectedMembers.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedMembers.length,
                          itemBuilder: (context, index) {
                            final member = _selectedMembers[index];
                            return Container(
                              margin: EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryBlue.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          member['name']?.toString() ?? 'Unknown',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(999),
                                        onTap: () => _toggleUserSelection(member),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.16),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    
                    // Search users
                    Material(
                      color: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.black12,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                        side: BorderSide(
                          color: AppTheme.lightGray.withValues(alpha: 0.7),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: tt.bodyLarge?.copyWith(color: AppTheme.darkSlate),
                        decoration: InputDecoration(
                          hintText: 'Search users',
                          hintStyle: TextStyle(color: AppTheme.mediumGray, fontSize: 15),
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: AppTheme.mediumGray,
                            size: 22,
                          ),
                          filled: false,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                        ),
                        onChanged: _searchUsers,
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // Users list
                    Expanded(
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final isSelected = _selectedMembers.any((m) => m['uid'] == user['uid']);
                          
                          return Container(
                            margin: EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected 
                                    ? AppTheme.primaryBlue.withOpacity(0.3)
                                    : AppTheme.primaryBlue.withOpacity(0.1),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryBlue.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              leading: Container(
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryBlue.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: UserAvatar(
                                  name: user['name']?.toString() ?? 'U',
                                  profilePhotoBase64:
                                      user['profilePhotoBase64'] as String?,
                                  photoUrl: user['photoUrl'] as String?,
                                  radius: 22,
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              title: Text(
                                user['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkSlate,
                                ),
                              ),
                              subtitle: Text(
                                user['email'],
                                style: TextStyle(color: AppTheme.mediumGray),
                              ),
                              trailing: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: isSelected ? AppTheme.accentGradient : null,
                                  color: isSelected ? null : AppTheme.lightGray,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: isSelected ? Colors.white : AppTheme.mediumGray,
                                  size: 24,
                                ),
                              ),
                              onTap: () => _toggleUserSelection(user),
                            ),
                          );
                        },
                      ),
                    ),
                    
                    // Create button
                    Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: _isCreating ? null : AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _isCreating ? null : [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withOpacity(0.3),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isCreating ? null : _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isCreating ? AppTheme.mediumGray : Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: _isCreating
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Creating...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.group_add, color: Colors.white, size: 24),
                                  SizedBox(width: 12),
                                  Text(
                                    'Create Group',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      );
  }
}
