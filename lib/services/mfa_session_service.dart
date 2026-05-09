import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MFASessionService {
  static final _storage = FlutterSecureStorage();
  static const String _sessionKey = 'mfa_session_completed';
  static const Duration _mfaSessionTtl = Duration(hours: 12);
  
  static Future<bool> hasCompletedMFA() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final raw = await _storage.read(key: '${_sessionKey}_${user.uid}');
      if (raw == null || raw.isEmpty) return false;
      final completedAt = DateTime.tryParse(raw);
      if (completedAt == null) {
        await _storage.delete(key: '${_sessionKey}_${user.uid}');
        return false;
      }
      final age = DateTime.now().difference(completedAt);
      if (age > _mfaSessionTtl) {
        await _storage.delete(key: '${_sessionKey}_${user.uid}');
        return false;
      }
      return true;
    } catch (e) {
      print('Error checking MFA session: $e');
      return false;
    }
  }
  
  static Future<void> markMFACompleted() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final now = DateTime.now().toIso8601String();
      await _storage.write(key: '${_sessionKey}_${user.uid}', value: now);
      print('MFA session marked as completed for user: ${user.uid}');
    } catch (e) {
      print('Error marking MFA as completed: $e');
    }
  }
  
  static Future<void> clearMFASession() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      await _storage.delete(key: '${_sessionKey}_${user.uid}');
      print('MFA session cleared for user: ${user.uid}');
    } catch (e) {
      print('Error clearing MFA session: $e');
    }
  }
  
  static Future<void> forceMFARequired() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      await _storage.delete(key: '${_sessionKey}_${user.uid}');
      print('MFA session cleared - MFA will be required on next login');
    } catch (e) {
      print('Error forcing MFA required: $e');
    }
  }
}
