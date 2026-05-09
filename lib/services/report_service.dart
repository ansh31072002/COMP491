import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Stream<QuerySnapshot> recentReportsStream({int limit = 50}) {
    return _firestore
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  static Future<void> submitUserReport({
    required String reportedUserId,
    required String reportedEmail,
    required String reason,
    required String details,
    String? chatId,
  }) async {
    final reporter = _auth.currentUser;
    if (reporter == null) {
      throw StateError('Not authenticated');
    }
    if (details.trim().isEmpty) {
      throw ArgumentError('Report details are required.');
    }
    final reporterEmail = reporter.email ?? '';

    await _firestore.collection('reports').add({
      'type': 'user',
      'status': 'open', // open | resolved
      'reason': reason,
      'details': details.trim(),
      'chatId': chatId,
      'reportedUserId': reportedUserId,
      'reportedEmail': reportedEmail,
      'reporterUserId': reporter.uid,
      'reporterEmail': reporterEmail,
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
      'resolvedByUserId': null,
      'resolutionNote': null,
    });
  }

  static Future<void> setReportResolved({
    required String reportId,
    required bool resolved,
    String? resolutionNote,
  }) async {
    final current = _auth.currentUser;
    if (current == null) throw StateError('Not authenticated');

    await _firestore.collection('reports').doc(reportId).update({
      'status': resolved ? 'resolved' : 'open',
      'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      'resolvedByUserId': resolved ? current.uid : null,
      'resolutionNote': resolved ? (resolutionNote ?? '') : null,
    });
  }
}

