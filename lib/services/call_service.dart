import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/call_session.dart';

/// Handles call creation and Firestore signaling for WebRTC.
/// WebRTC peer connection and media are typically managed in the call screen.
class CallService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _callsCollection = 'calls';

  /// Start a new call: create document and return callId. Caller then creates offer in CallScreen.
  static Future<String> createCall({
    required String calleeId,
    required String calleeName,
    required bool isVideo,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final ref = _firestore.collection(_callsCollection).doc();
    final callId = ref.id;
    await ref.set({
      'callId': callId,
      'callerId': user.uid,
      'callerName': user.displayName ?? user.email?.split('@').first ?? 'User',
      'calleeId': calleeId,
      'calleeName': calleeName,
      'type': isVideo ? 'video' : 'audio',
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': [user.uid, calleeId],
    });
    return callId;
  }

  /// Stream of incoming calls for the current user (callee, status ringing).
  static Stream<CallSession?> incomingCallsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection(_callsCollection)
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          final doc = snap.docs.first;
          return CallSession.fromMap(doc.data(), doc.id);
        });
  }

  /// Single call document stream (for caller and callee to exchange offer/answer/ICE).
  static Stream<DocumentSnapshot> callDocStream(String callId) {
    return _firestore.collection(_callsCollection).doc(callId).snapshots();
  }

  /// Get current call data once.
  static Future<CallSession?> getCall(String callId) async {
    final doc = await _firestore.collection(_callsCollection).doc(callId).get();
    return CallSession.fromMap(doc.data(), doc.id);
  }

  /// Update call status (connected, ended, declined).
  /// Sets [connectedAt] when status is [connected], [endedAt] when ended or declined.
  /// For [ended], pass [durationSeconds] when the call had been connected (for history).
  static Future<void> updateCallStatus(
    String callId,
    String status, {
    int? durationSeconds,
  }) async {
    final updates = <String, dynamic>{'status': status};
    if (status == 'connected') {
      updates['connectedAt'] = FieldValue.serverTimestamp();
    }
    if (status == 'ended' || status == 'declined') {
      updates['endedAt'] = FieldValue.serverTimestamp();
      if (status == 'ended' &&
          durationSeconds != null &&
          durationSeconds >= 0) {
        updates['durationSeconds'] = durationSeconds;
      }
    }
    await _firestore.collection(_callsCollection).doc(callId).update(updates);
  }

  /// Caller writes SDP offer to Firestore.
  static Future<void> setOffer(String callId, Map<String, dynamic> offer) async {
    await _firestore.collection(_callsCollection).doc(callId).update({'offer': offer});
  }

  /// Callee writes SDP answer to Firestore.
  static Future<void> setAnswer(String callId, Map<String, dynamic> answer) async {
    await _firestore.collection(_callsCollection).doc(callId).update({'answer': answer});
  }

  /// Append ICE candidate from caller (array field).
  static Future<void> addIceCandidateCaller(String callId, Map<String, dynamic> candidate) async {
    final ref = _firestore.collection(_callsCollection).doc(callId);
    await ref.update({
      'iceCandidatesCaller': FieldValue.arrayUnion([candidate]),
    });
  }

  /// Append ICE candidate from callee (array field).
  static Future<void> addIceCandidateCallee(String callId, Map<String, dynamic> candidate) async {
    final ref = _firestore.collection(_callsCollection).doc(callId);
    await ref.update({
      'iceCandidatesCallee': FieldValue.arrayUnion([candidate]),
    });
  }

  /// Decline an incoming call.
  static Future<void> declineCall(String callId) async {
    await updateCallStatus(callId, 'declined');
  }

  /// Poll until the caller has written an SDP offer (or [timeout] elapses).
  static Future<Map<String, dynamic>?> waitForOffer(
    String callId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final doc = await _firestore.collection(_callsCollection).doc(callId).get();
      final offer = doc.data()?['offer'] as Map<String, dynamic>?;
      final sdp = offer?['sdp'] as String?;
      if (sdp != null && sdp.isNotEmpty) return offer;
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }
}
