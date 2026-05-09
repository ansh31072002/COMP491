import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Avatar from optional [profilePhotoBase64], optional [photoUrl] (HTTPS), else initials.
///
/// Decodes base64 once per unique string (Stateful) so [Image.memory] does not
/// restart every parent rebuild — that was causing flicker/twitching.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.profilePhotoBase64,
    this.photoUrl,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String name;
  final String? profilePhotoBase64;
  final String? photoUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  static String initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  static Uint8List? tryDecodeBase64(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      return base64Decode(t);
    } catch (_) {
      return null;
    }
  }

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  /// Stable image provider; only recreated when base64 string changes.
  MemoryImage? _memoryImage;
  String? _cachedB64;

  String? _cachedUrl;
  NetworkImage? _networkImage;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profilePhotoBase64 != widget.profilePhotoBase64 ||
        oldWidget.photoUrl != widget.photoUrl) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    final b64 = widget.profilePhotoBase64?.trim();
    if (b64 == null || b64.isEmpty) {
      _memoryImage = null;
      _cachedB64 = null;
    } else if (b64 != _cachedB64) {
      _cachedB64 = b64;
      final bytes = UserAvatar.tryDecodeBase64(b64);
      _memoryImage =
          bytes != null && bytes.isNotEmpty ? MemoryImage(bytes) : null;
    }

    final u = widget.photoUrl?.trim();
    if (u == null || u.isEmpty || !u.startsWith('http')) {
      _networkImage = null;
      _cachedUrl = null;
    } else if (u != _cachedUrl) {
      _cachedUrl = u;
      _networkImage = NetworkImage(u);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppTheme.primaryBlue;
    final fg = widget.foregroundColor ?? Colors.white;
    final r = widget.radius;

    final mem = _memoryImage;
    if (mem != null) {
      return RepaintBoundary(
        child: CircleAvatar(
          radius: r,
          backgroundColor: bg,
          backgroundImage: mem,
          onBackgroundImageError: (_, __) {
            if (mounted) {
              setState(() {
                _memoryImage = null;
                _cachedB64 = null;
              });
            }
          },
        ),
      );
    }

    final net = _networkImage;
    if (net != null) {
      return RepaintBoundary(
        child: CircleAvatar(
          radius: r,
          backgroundColor: bg,
          backgroundImage: net,
          onBackgroundImageError: (_, __) {
            if (mounted) {
              setState(() {
                _networkImage = null;
                _cachedUrl = null;
              });
            }
          },
        ),
      );
    }

    return RepaintBoundary(
      child: CircleAvatar(
        radius: r,
        backgroundColor: bg,
        child: Text(
          UserAvatar.initialsFromName(widget.name),
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: r * 0.75,
          ),
        ),
      ),
    );
  }
}
