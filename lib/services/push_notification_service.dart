import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> initialize({
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    try {
      await _requestPermissions();
    } catch (e) {
      debugPrint('PushNotificationService: permission request failed: $e');
    }

    try {
      await _updateFcmToken();
    } catch (e) {
      debugPrint(
        'PushNotificationService: FCM token unavailable (fix Android app in '
        'Firebase Console + google-services.json / flutterfire configure): $e',
      );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        _saveToken(token).catchError((Object e) {
          debugPrint('PushNotificationService: token save failed: $e');
        });
      },
      onError: (Object e) {
        debugPrint('PushNotificationService: onTokenRefresh: $e');
      },
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final title = notification?.title ?? 'New notification';
      final body = notification?.body ?? '';
      final context = navigatorKey?.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body.isEmpty ? title : '$title\n$body'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      debugPrint('FCM foreground message: $title - $body');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationNavigation(message, navigatorKey);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationNavigation(initialMessage, navigatorKey);
    }
  }

  static void _handleNotificationNavigation(
    RemoteMessage message,
    GlobalKey<NavigatorState>? navigatorKey,
  ) {
    final context = navigatorKey?.currentContext;
    if (context == null) {
      debugPrint('PushNotificationService: no navigation context for message');
      return;
    }
    final data = message.data;
    final title = message.notification?.title ?? 'Notification opened';
    final body = message.notification?.body ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title\n$body'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    debugPrint('FCM open payload: $data');
  }

  static Future<void> _requestPermissions() async {
    if (kIsWeb) {
      await _messaging.requestPermission();
      return;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } else {
      await _messaging.requestPermission();
    }
  }

  static Future<void> _updateFcmToken() async {
    final token = await _messaging.getToken();
    if (token == null) return;
    try {
      await _saveToken(token);
    } catch (e) {
      debugPrint('PushNotificationService: could not persist token: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userRef = _firestore.collection('users').doc(user.uid);
    await userRef.set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
      },
      SetOptions(merge: true),
    );
  }
}

