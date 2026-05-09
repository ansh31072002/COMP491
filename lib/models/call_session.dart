/// Represents a call for UI and signaling.
class CallSession {
  final String callId;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String type; // 'audio' | 'video'
  final String status; // 'ringing' | 'connected' | 'ended' | 'declined'

  CallSession({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.type,
    required this.status,
  });

  bool get isVideo => type == 'video';
  bool get isRinging => status == 'ringing';
  bool get isConnected => status == 'connected';
  bool get isEnded => status == 'ended' || status == 'declined';

  static CallSession? fromMap(Map<String, dynamic>? data, String docId) {
    if (data == null) return null;
    return CallSession(
      callId: docId,
      callerId: data['callerId'] as String? ?? '',
      callerName: data['callerName'] as String? ?? 'Unknown',
      calleeId: data['calleeId'] as String? ?? '',
      type: data['type'] as String? ?? 'audio',
      status: data['status'] as String? ?? 'ringing',
    );
  }
}
