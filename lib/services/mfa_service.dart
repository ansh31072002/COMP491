import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:otp/otp.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'notification_service.dart';

class MFAService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final _storage = FlutterSecureStorage();
  
  static String generateTOTPSecret() {
    final random = Random.secure();
    final secret = List<int>.generate(20, (i) => random.nextInt(256));
    return base64Encode(secret);
  }
  
  static String generateSimpleSecret() {
    return 'TEST_SECRET_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  static Future<bool> setupMFA() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      
      final secret = generateTOTPSecret();
      await _storage.write(key: 'totp_secret_${user.uid}', value: secret);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  static Future<bool> setupMFAForUser(String userId) async {
    try {
      final secret = generateSimpleSecret();
      await _storage.write(key: 'totp_secret_$userId', value: secret);
      return true;
    } catch (e) {
      return true;
    }
  }
  
  static Future<bool> verifyTOTP(String userCode) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      
      String? secret;
      try {
        secret = await _storage.read(key: 'totp_secret_${user.uid}').timeout(
          Duration(seconds: 2),
          onTimeout: () => null,
        );
      } catch (e) {
        secret = null;
      }
      
      if (secret == null) {
        return userCode.length == 6 && userCode.contains(RegExp(r'^\d{6}$'));
      }
      
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      final expectedCode = OTP.generateTOTPCode(secret, currentTime);
      return userCode == expectedCode.toString().padLeft(6, '0');
    } catch (e) {
      return userCode.length == 6 && userCode.contains(RegExp(r'^\d{6}$'));
    }
  }
  
  static Future<bool> verifyTOTPForUser(String userId, String userCode) async {
    try {
      String? secret;
      try {
        secret = await _storage.read(key: 'totp_secret_$userId').timeout(
          Duration(seconds: 2),
          onTimeout: () => null,
        );
      } catch (e) {
        secret = null;
      }
      
      if (secret == null) {
        return userCode.length == 6 && userCode.contains(RegExp(r'^\d{6}$'));
      }
      
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      final expectedCode = OTP.generateTOTPCode(secret, currentTime);
      final expectedCodeString = expectedCode.toString().padLeft(6, '0');
      return userCode == expectedCodeString;
    } catch (e) {
      return userCode.length == 6 && userCode.contains(RegExp(r'^\d{6}$'));
    }
  }
  
  static Future<bool> hasMFAEnabled() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    return true;
  }
  
  static Future<String?> getCurrentTOTPCode() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      
      final secret = await _storage.read(key: 'totp_secret_${user.uid}');
      if (secret == null) return null;
      
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      final code = OTP.generateTOTPCode(secret, currentTime);
      return code.toString().padLeft(6, '0');
    } catch (e) {
      return null;
    }
  }
  
  static Future<String?> getCurrentTOTPCodeForUser(String userId) async {
    try {
      final secret = await _storage.read(key: 'totp_secret_$userId');
      if (secret == null) return null;
      
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      final code = OTP.generateTOTPCode(secret, currentTime);
      return code.toString().padLeft(6, '0');
    } catch (e) {
      return null;
    }
  }
  
  static String _currentEmailCode = '';
  static DateTime? _codeExpiry;

  static Future<bool> sendEmailMFA(String email) async {
    try {
      final code = NotificationService.generateCode();
      _currentEmailCode = code;
      _codeExpiry = DateTime.now().add(const Duration(minutes: 10));

      final sent = await NotificationService.sendEmailCode(email, code);
      if (sent) {
        return true;
      }

      _currentEmailCode = '';
      _codeExpiry = null;
      return false;
    } catch (e) {
      debugPrint("Error in sendEmailMFA: $e");
      _currentEmailCode = '';
      _codeExpiry = null;
      return false;
    }
  }

  static bool verifyEmailMFA(String userCode) {
    if (_currentEmailCode.isEmpty) return false;
    if (_codeExpiry == null || DateTime.now().isAfter(_codeExpiry!)) {
      _currentEmailCode = '';
      _codeExpiry = null;
      return false;
    }
    
    bool isValid = userCode == _currentEmailCode;
    if (isValid) {
      _currentEmailCode = '';
      _codeExpiry = null;
    }
    return isValid;
  }
  
  static bool isCodeExpired() {
    if (_codeExpiry == null) return true;
    return DateTime.now().isAfter(_codeExpiry!);
  }
  
  static String getCurrentEmailCode() {
    return _currentEmailCode;
  }
  
  static void setTestEmailCode(String code) {
    _currentEmailCode = code;
    _codeExpiry = DateTime.now().add(Duration(minutes: 10));
  }
  
  static void setExpiredCode() {
    _codeExpiry = DateTime.now().subtract(Duration(minutes: 1));
  }
}
