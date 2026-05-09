import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/notification_config.dart';

class NotificationService {
  static bool _testMode = false;
  
  static void enableTestMode() {
    _testMode = true;
  }
  
  static String generateCode() {
    Random random = Random();
    int code = random.nextInt(900000) + 100000;
    return code.toString();
  }
  
  static Future<bool> sendEmailCode(String email, String code) async {
    if (_testMode) {
      return sendTestCode('Email', email, code);
    }
    
    try {
      String subject = "Your SECURELY MFA Code";
      String body = "Your verification code is: $code\n\nThis code expires in 10 minutes.\n\nIf you didn't request this code, please ignore this email.";
      
      if (kDebugMode) {
        debugPrint(
          'EmailJS send → $email (service=${NotificationConfig.EMAILJS_SERVICE_ID})',
        );
      }
      
      final payload = <String, dynamic>{
        'service_id': NotificationConfig.EMAILJS_SERVICE_ID,
        'template_id': NotificationConfig.EMAILJS_TEMPLATE_ID,
        'user_id': NotificationConfig.EMAILJS_USER_ID,
        'template_params': {
          'to_email': email,
          'to_name': 'User',
          'subject': subject,
          'message': body,
          'reply_to': email,
          'from_name': 'SECURELY App',
          'from_email': 'noreply@securely.app',
          'code': code,
          'user_email': email,
          'verification_code': code,
        },
      };
      if (NotificationConfig.EMAILJS_PRIVATE_KEY.isNotEmpty) {
        payload['accessToken'] = NotificationConfig.EMAILJS_PRIVATE_KEY;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent':
            'SECURELY/1.0 (Flutter; Android/iOS; like EmailJS-REST)',
      };
      if (NotificationConfig.EMAILJS_REQUEST_ORIGIN.isNotEmpty) {
        headers['Origin'] = NotificationConfig.EMAILJS_REQUEST_ORIGIN;
      }

      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: headers,
        body: jsonEncode(payload),
      );
      
      debugPrint("EmailJS response: ${response.statusCode} ${response.body}");
      
      if (response.statusCode == 200) {
        debugPrint("Email sent successfully to: $email");
        return true;
      }

      debugPrint(
        "EmailJS failed: HTTP ${response.statusCode} — ${response.body}",
      );
      debugPrint(
        "Check EmailJS template params match (e.g. code, to_email) and service limits.",
      );
      if (kDebugMode) {
        debugPrint("═══ MFA debug: intended code for $email → $code ═══");
      }
      return false;
    } catch (e) {
      debugPrint("Error sending email: $e");
      if (kDebugMode) {
        debugPrint("═══ MFA debug: intended code for $email → $code ═══");
      }
      return false;
    }
  }
  
  static Future<bool> sendTestCode(String method, String contact, String code) async {
    debugPrint("MFA test: $method → $contact code=$code");

    await Future.delayed(Duration(seconds: 1));
    return true;
  }
}
