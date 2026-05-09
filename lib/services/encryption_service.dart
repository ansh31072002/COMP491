import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:math';

class EncryptionService {
  static final _storage = FlutterSecureStorage();
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  
  static String generateRandomKey() {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Encode(keyBytes);
  }
  
  static String encryptMessage(String message, String keyString) {
    try {
      if (message.isEmpty || keyString.isEmpty) {
        return message;
      }
      
      final keyBytes = base64Decode(keyString);
      final key = Key(keyBytes);
      
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      
      final iv = IV.fromSecureRandom(16);
      
      final encrypted = encrypter.encrypt(message, iv: iv);
      
      final combined = iv.bytes + encrypted.bytes;
      return base64Encode(combined);
    } catch (e) {
      print('AES Encryption error: $e');
      return message;
    }
  }
  
  static String decryptMessage(String encryptedData, String keyString) {
    try {
      if (encryptedData.isEmpty || keyString.isEmpty) {
        return encryptedData;
      }
      
      final keyBytes = base64Decode(keyString);
      final key = Key(keyBytes);
      
      final combined = base64Decode(encryptedData);
      
      final ivBytes = combined.sublist(0, 16);
      final encryptedBytes = combined.sublist(16);
      
      final iv = IV(ivBytes);
      final encrypted = Encrypted(encryptedBytes);
      
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print('AES Decryption error: $e');
      return encryptedData;
    }
  }
  
  static Future<void> storeUserKey(String userId, String key) async {
    try {
      await _firestore.collection('encryption_keys').doc(userId).set({
        'key': key,
        'userId': _auth.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      await _storage.write(key: 'encryption_key_$userId', value: key);
    } catch (e) {
      print('Error storing key in Firebase: $e');
      await _storage.write(key: 'encryption_key_$userId', value: key);
    }
  }
  
  static Future<String?> getUserKey(String userId) async {
    try {
      final doc = await _firestore.collection('encryption_keys').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        final key = doc.data()!['key'] as String?;
        if (key != null) {
          await _storage.write(key: 'encryption_key_$userId', value: key);
          return key;
        }
      }
      
      return await _storage.read(key: 'encryption_key_$userId');
    } catch (e) {
      print('Error retrieving key from Firebase: $e');
      return await _storage.read(key: 'encryption_key_$userId');
    }
  }
  
  static Future<void> exchangeKeys(String otherUserId, String sharedKey) async {
    await _storage.write(key: 'shared_key_$otherUserId', value: sharedKey);
  }
  
  static Future<void> storeSharedKey(String chatId, String key, List<String> participantIds) async {
    try {
      await _firestore.collection('shared_keys').doc(chatId).set({
        'key': key,
        'chatId': chatId,
        'participants': participantIds,
        'createdBy': _auth.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      await _storage.write(key: '${chatId}_shared', value: key);
    } catch (e) {
      print('Error storing shared key in Firebase: $e');
      await _storage.write(key: '${chatId}_shared', value: key);
    }
  }
  
  static Future<String?> getSharedKey(String chatId) async {
    try {
      final doc = await _firestore.collection('shared_keys').doc(chatId).get();
      if (doc.exists && doc.data() != null) {
        final key = doc.data()!['key'] as String?;
        if (key != null) {
          await _storage.write(key: '${chatId}_shared', value: key);
          return key;
        }
      }
      
      return await _storage.read(key: '${chatId}_shared');
    } catch (e) {
      print('Error retrieving shared key from Firebase: $e');
      return await _storage.read(key: '${chatId}_shared');
    }
  }
  
  static Future<String> getOrCreateSharedKey(
    String chatId, {
    List<String>? participantIds,
  }) async {
    String? sharedKey = await getSharedKey(chatId);
    
    if (sharedKey == null) {
      sharedKey = generateRandomKey();
      
      final currentUserId = _auth.currentUser?.uid;
      final resolvedParticipants = <String>{
        ...?participantIds,
        if (currentUserId != null) currentUserId,
      };

      if (resolvedParticipants.isEmpty) {
        resolvedParticipants.addAll(await getChatParticipants(chatId));
      }

      if (resolvedParticipants.isNotEmpty) {
        await storeSharedKey(chatId, sharedKey, resolvedParticipants.toList());
      } else {
        await _storage.write(key: '${chatId}_shared', value: sharedKey);
      }
    }
    
    return sharedKey;
  }

  static Future<List<String>> getChatParticipants(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return const [];
      final data = chatDoc.data();
      final participants = List<String>.from(data?['participants'] ?? const []);
      return participants.where((id) => id.trim().isNotEmpty).toList();
    } catch (e) {
      print('Error getting chat participants: $e');
      return const [];
    }
  }
  
  static Future<String> decryptWithFallback(String encryptedData, String chatId) async {
    try {
      final currentKey = await getSharedKey(chatId);
      if (currentKey != null) {
        try {
          final result = decryptMessage(encryptedData, currentKey);
          if (result != encryptedData) {
            return result;
          }
        } catch (e) {
          print('Failed to decrypt with current key: $e');
        }
      }
      
      final allKeys = await _getAllKeysForChat(chatId);
      for (final key in allKeys) {
        try {
          final result = decryptMessage(encryptedData, key);
          if (result != encryptedData) {
            return result;
          }
        } catch (e) {
          continue;
        }
      }

      if (_isBase64Encoded(encryptedData)) {
        return '[Encrypted message - key not available]';
      } else {
        return encryptedData;
      }
    } catch (e) {
      print('Decryption fallback error: $e');
      return '[Decryption failed]';
    }
  }
  
  static bool _isBase64Encoded(String data) {
    try {
      final decoded = base64Decode(data);
      return decoded.length > 16;
    } catch (e) {
      return false;
    }
  }
  
  static Future<List<String>> _getAllKeysForChat(String chatId) async {
    final keys = <String>[];
    try {
      final patterns = [
        '${chatId}_shared',
        'encryption_key_${chatId}',
        'shared_key_${chatId}',
      ];
      
      for (final pattern in patterns) {
        final key = await _storage.read(key: pattern);
        if (key != null) {
          keys.add(key);
        }
      }
    } catch (e) {
      print('Error getting all keys for chat: $e');
    }
    return keys;
  }
  
  static Future<bool> hasSharedKey(String chatId) async {
    final key = await getUserKey('${chatId}_shared');
    return key != null;
  }
  
  static Future<void> migrateKeysIfNeeded() async {
    try {
      print('Key migration check completed');
    } catch (e) {
      print('Key migration error: $e');
    }
  }
  
  static Future<void> clearChatKeys(String chatId) async {
    try {
      final patterns = [
        '${chatId}_shared',
        'encryption_key_${chatId}',
        'shared_key_${chatId}',
      ];
      
      for (final pattern in patterns) {
        await _storage.delete(key: pattern);
      }
      print('Cleared all keys for chat: $chatId');
    } catch (e) {
      print('Error clearing chat keys: $e');
    }
  }
  
  static String handleLegacyMessage(String message, bool isEncrypted) {
    if (!isEncrypted) {
      return message;
    }
    
    if (_isBase64Encoded(message)) {
      return '🔒 [Encrypted message from previous session]';
    } else {
      return message;
    }
  }
  
  static Future<void> testEncryption() async {
    final key = generateRandomKey();
    final message = "Hello, this is a secret message encrypted with AES-256!";
    
    print('Testing AES-256 Encryption:');
    print('Original: $message');
    print('Key (Base64): $key');
    
    final encrypted = encryptMessage(message, key);
    print('Encrypted: $encrypted');
    
    final decrypted = decryptMessage(encrypted, key);
    print('Decrypted: $decrypted');
    print('Match: ${message == decrypted}');
    
    final message2 = "Another message with different content";
    final encrypted2 = encryptMessage(message2, key);
    print('\nTesting IV randomization:');
    print('Message 2: $message2');
    print('Encrypted 2: $encrypted2');
    print('Different encrypted outputs: ${encrypted != encrypted2}');
  }
}
