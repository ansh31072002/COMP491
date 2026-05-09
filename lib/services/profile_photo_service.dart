import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stores profile images in Firestore as base64 (JPEG/PNG bytes), field [profilePhotoBase64].
/// Firestore documents are limited to 1 MiB — keep images small (picker compresses).
class ProfilePhotoService {
  ProfilePhotoService._();

  /// ~700 KB raw binary keeps the user doc under the 1 MiB limit with headroom.
  static const int maxBytes = 700000;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Saves [bytes] as base64 on `users/{uid}` and clears legacy [photoUrl] if present.
  /// Does not use Firebase Storage. Does not set Auth [photoURL] (HTTPS-only in Auth).
  static Future<void> saveProfilePhotoBytes(String uid, List<int> bytes) async {
    if (bytes.length > maxBytes) {
      throw Exception('Image too large for Firestore. Use a smaller image.');
    }
    final b64 = base64Encode(Uint8List.fromList(bytes));
    await _firestore.collection('users').doc(uid).set(
      {
        'profilePhotoBase64': b64,
        'photoUrl': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  /// Clears stored photo fields. Clears Auth [photoURL] if set.
  static Future<void> removeProfilePhoto(String uid) async {
    await _firestore.collection('users').doc(uid).set(
      {
        'profilePhotoBase64': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
    final user = _auth.currentUser;
    if (user != null && user.uid == uid) {
      try {
        await user.updatePhotoURL(null);
        await user.reload();
      } catch (_) {}
    }
  }
}
