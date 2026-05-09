import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Writes audit events to Firestore `audit_logs`.
/// Restrict read in Firestore rules to managers; writes from authenticated users.
class AuditService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'audit_logs';

  static Future<void> _add(String action, Map<String, dynamic> data) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await _firestore.collection(_collection).add({
        'action': action,
        'actorId': uid ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        ...data,
      });
    } catch (_) {
      // Don't block app flow if audit write fails
    }
  }

  /// Log login success or failure.
  static Future<void> logLogin({
    required bool success,
    String? userId,
    String? email,
  }) async {
    await _add('login', {
      'success': success,
      if (userId != null) 'userId': userId,
      if (email != null) 'email': email,
    });
  }

  /// Log logout (call before signOut so currentUser is still set).
  static Future<void> logLogout({String? userId, String? email}) async {
    await _add('logout', {
      if (userId != null) 'userId': userId,
      if (email != null) 'email': email,
    });
  }

  /// Log MFA verification success or failure.
  static Future<void> logMfa({
    required bool success,
    String? userId,
    String? email,
  }) async {
    await _add('mfa_verify', {
      'success': success,
      if (userId != null) 'userId': userId,
      if (email != null) 'email': email,
    });
  }

  /// Log role change (who changed whom, old/new role). Actor = current user.
  static Future<void> logRoleChange({
    required String targetUserId,
    required String targetEmail,
    required String oldRole,
    required String newRole,
  }) async {
    await _add('role_change', {
      'targetUserId': targetUserId,
      'targetEmail': targetEmail,
      'oldRole': oldRole,
      'newRole': newRole,
    });
  }

  /// Stream of recent audit entries (for Admin Panel). Order by timestamp desc.
  static Stream<QuerySnapshot> recentLogsStream({int limit = 50}) {
    return _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }
}
