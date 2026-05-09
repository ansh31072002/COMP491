import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/profile_photo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/user_avatar.dart';

/// Change display name (optional) and profile photo.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _busy = false;
  String? _profilePhotoBase64;
  /// Legacy HTTPS image from Storage or external (shown until user re-uploads in-app).
  String? _legacyPhotoUrl;
  String _email = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        _nameController.text = (data['name'] as String?)?.trim() ?? user.displayName ?? '';
        _profilePhotoBase64 = data['profilePhotoBase64'] as String?;
        _legacyPhotoUrl = data['photoUrl'] as String? ?? user.photoURL;
      } else {
        _nameController.text = user.displayName ?? '';
        _legacyPhotoUrl = user.photoURL;
      }
      _email = user.email ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > ProfilePhotoService.maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Image must be under ${(ProfilePhotoService.maxBytes / 1024).round()} KB after compression.',
              ),
              backgroundColor: AppTheme.warningOrange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      setState(() => _busy = true);
      await ProfilePhotoService.saveProfilePhotoBytes(user.uid, bytes);
      if (mounted) {
        setState(() {
          _profilePhotoBase64 = base64Encode(bytes);
          _legacyPhotoUrl = null;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile photo updated'),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update photo. Try again.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ProfilePhotoService.removeProfilePhoto(user.uid);
      if (mounted) {
        setState(() {
          _profilePhotoBase64 = null;
          _legacyPhotoUrl = null;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile photo removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Name cannot be empty'),
          backgroundColor: AppTheme.warningOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await user.updateDisplayName(name);
      await user.reload();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'name': name},
        SetOptions(merge: true),
      );
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile saved'),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.cardRadius)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: AppTheme.primaryBlue),
              title: Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: AppTheme.primaryBlue),
              title: Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final displayName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_email.split('@').isNotEmpty ? _email.split('@').first : 'You');

    return Scaffold(
      backgroundColor: AppTheme.surfaceGray,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text(
              'Profile',
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
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: UserAvatar(
                      name: displayName,
                      profilePhotoBase64: _profilePhotoBase64,
                      photoUrl: _legacyPhotoUrl,
                      radius: 56,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _showPhotoSourceSheet,
                        icon: Icon(Icons.add_a_photo_outlined, size: 20),
                        label: Text('Change photo'),
                      ),
                      if ((_profilePhotoBase64 != null &&
                              _profilePhotoBase64!.isNotEmpty) ||
                          (_legacyPhotoUrl != null &&
                              _legacyPhotoUrl!.isNotEmpty)) ...[
                        SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy ? null : _removePhoto,
                          child: Text(
                            'Remove',
                            style: TextStyle(color: AppTheme.errorRed),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Name',
                    style: tt.titleSmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _email,
                    style: tt.bodyMedium?.copyWith(color: AppTheme.mediumGray),
                  ),
                  SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _saveName,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                        ),
                      ),
                      child: Text('Save name'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
