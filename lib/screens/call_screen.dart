import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';

/// Voice or video call with WebRTC; Firestore carries SDP and ICE candidates.
class CallScreen extends StatefulWidget {
  final bool isIncoming;
  final String? callId;
  final String? calleeId;
  final String? calleeName;
  final String? callerName;
  final String? otherPhotoUrl;
  final String? otherPhotoBase64;
  final bool isVideo;

  const CallScreen.outgoing({
    Key? key,
    required this.calleeId,
    required this.calleeName,
    required this.isVideo,
    this.otherPhotoUrl,
    this.otherPhotoBase64,
  })  : isIncoming = false,
        callId = null,
        callerName = null,
        super(key: key);

  CallScreen.incoming({
    Key? key,
    required String callId,
    required String callerName,
    required bool isVideo,
    this.otherPhotoUrl,
    this.otherPhotoBase64,
  })  : isIncoming = true,
        callId = callId,
        calleeId = null,
        calleeName = null,
        callerName = callerName,
        isVideo = isVideo,
        super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const Map<String, dynamic> _pcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  String? _callId;
  String _status = 'ringing';
  StreamSubscription<DocumentSnapshot>? _callSub;
  bool _busy = false;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _videoRenderersReady = false;

  bool _webrtcRunning = false;
  bool _remoteDescriptionSet = false;
  bool _callerAnswerApplied = false;
  /// Set when the call becomes connected (from Firestore or locally after accept).
  DateTime? _callConnectedAt;
  final Set<String> _seenRemoteIceKeys = {};
  final List<RTCIceCandidate> _pendingRemoteIce = [];

  @override
  void initState() {
    super.initState();
    if (widget.isIncoming) {
      _callId = widget.callId;
      _listenToCall();
    } else {
      _startOutgoingCall();
    }
  }

  Future<void> _startOutgoingCall() async {
    if (widget.calleeId == null || widget.calleeName == null) return;
    setState(() => _busy = true);
    try {
      final id = await CallService.createCall(
        calleeId: widget.calleeId!,
        calleeName: widget.calleeName!,
        isVideo: widget.isVideo,
      );
      if (!mounted) return;
      setState(() {
        _callId = id;
        _busy = false;
      });
      _listenToCall();
      unawaited(_startCallerWebRtc());
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start call. Try again.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _listenToCall() {
    if (_callId == null) return;
    _callSub?.cancel();
    _callSub = CallService.callDocStream(_callId!).listen(
      _onCallDocument,
      onError: (_) {},
    );
  }

  void _onCallDocument(DocumentSnapshot snap) {
    if (!mounted) return;
    final data = snap.data() as Map<String, dynamic>?;
    if (data == null) return;

    final status = data['status'] as String?;
    if (status != null && status != _status) {
      setState(() {
        _status = status;
        if (status == 'connected') {
          final ct = data['connectedAt'];
          _callConnectedAt = ct is Timestamp ? ct.toDate() : DateTime.now();
        }
      });
      if (status == 'ended') {
        _handleRemoteEnd(declined: false);
        return;
      }
      if (status == 'declined') {
        _handleRemoteEnd(declined: true);
        return;
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final callerId = data['callerId'] as String?;
    final isCaller = uid != null && callerId == uid;

    if (isCaller && _pc != null && _webrtcRunning) {
      unawaited(_applyRemoteAnswerIfNeeded(data));
      _ingestIceList(data['iceCandidatesCallee']);
    } else if (!isCaller && _pc != null) {
      _ingestIceList(data['iceCandidatesCaller']);
    }
  }

  Future<void> _applyRemoteAnswerIfNeeded(Map<String, dynamic> data) async {
    if (_callerAnswerApplied || _pc == null) return;
    final answer = data['answer'] as Map<String, dynamic>?;
    final sdp = answer?['sdp'] as String?;
    final type = answer?['type'] as String?;
    if (sdp == null || type == null || sdp.isEmpty) return;
    _callerAnswerApplied = true;
    try {
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
      if (!mounted) return;
      setState(() => _remoteDescriptionSet = true);
      await _flushPendingIce();
    } catch (e) {
      _callerAnswerApplied = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not complete connection.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _ingestIceList(dynamic raw) {
    if (raw is! List || _pc == null) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      unawaited(_addRemoteIceCandidate(m));
    }
  }

  Future<void> _addRemoteIceCandidate(Map<String, dynamic> m) async {
    final cand = m['candidate'] as String?;
    if (cand == null || cand.isEmpty || _pc == null) return;
    final key = '$cand${m['sdpMid']}';
    if (_seenRemoteIceKeys.contains(key)) return;
    _seenRemoteIceKeys.add(key);
    final candidate = RTCIceCandidate(
      cand,
      m['sdpMid'] as String?,
      (m['sdpMLineIndex'] as num?)?.toInt() ?? 0,
    );
    if (!_remoteDescriptionSet) {
      _pendingRemoteIce.add(candidate);
      return;
    }
    try {
      await _pc!.addCandidate(candidate);
    } catch (_) {}
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null) return;
    for (final c in _pendingRemoteIce) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingRemoteIce.clear();
  }

  Future<void> _ensureVideoRenderers() async {
    if (!widget.isVideo) return;
    if (_videoRenderersReady) return;
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();
    await _remoteRenderer!.initialize();
    if (!mounted) return;
    setState(() => _videoRenderersReady = true);
  }

  Future<void> _startCallerWebRtc() async {
    if (_callId == null || _webrtcRunning || widget.isIncoming) return;
    try {
      await _ensureVideoRenderers();
      _pc = await createPeerConnection(_pcConfig);
      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty && _remoteRenderer != null) {
          _remoteRenderer!.srcObject = event.streams[0];
          if (mounted) setState(() {});
        }
      };
      _pc!.onIceCandidate = (RTCIceCandidate event) {
        final c = event.candidate;
        if (c == null || c.isEmpty || _callId == null) return;
        unawaited(
          CallService.addIceCandidateCaller(
            _callId!,
            Map<String, dynamic>.from(event.toMap() as Map),
          ),
        );
      };

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      if (_localRenderer != null) {
        _localRenderer!.srcObject = _localStream;
      }
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }

      final offer = await _pc!.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': widget.isVideo});
      await _pc!.setLocalDescription(offer);
      await CallService.setOffer(_callId!, {'type': offer.type, 'sdp': offer.sdp});
      if (mounted) {
        setState(() => _webrtcRunning = true);
      }
    } catch (e) {
      if (_callId != null) {
        unawaited(CallService.updateCallStatus(_callId!, 'ended'));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Microphone or camera permission is required for calls.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
      await _disposeWebRtc();
    }
  }

  Future<void> _startCalleeWebRtc() async {
    if (_callId == null || _webrtcRunning) return;
    try {
      final offerMap = await CallService.waitForOffer(_callId!);
      if (offerMap == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Call setup timed out.'),
              backgroundColor: AppTheme.errorRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await _ensureVideoRenderers();
      _pc = await createPeerConnection(_pcConfig);
      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty && _remoteRenderer != null) {
          _remoteRenderer!.srcObject = event.streams[0];
          if (mounted) setState(() {});
        }
      };
      _pc!.onIceCandidate = (RTCIceCandidate event) {
        final c = event.candidate;
        if (c == null || c.isEmpty || _callId == null) return;
        unawaited(
          CallService.addIceCandidateCallee(
            _callId!,
            Map<String, dynamic>.from(event.toMap() as Map),
          ),
        );
      };

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      if (_localRenderer != null) {
        _localRenderer!.srcObject = _localStream;
      }
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }

      final sdp = offerMap['sdp'] as String?;
      final type = offerMap['type'] as String?;
      if (sdp == null || type == null) return;

      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
      if (!mounted) return;
      setState(() {
        _remoteDescriptionSet = true;
        _webrtcRunning = true;
      });
      await _flushPendingIce();

      final answer = await _pc!.createAnswer({'offerToReceiveAudio': true, 'offerToReceiveVideo': widget.isVideo});
      await _pc!.setLocalDescription(answer);
      await CallService.setAnswer(_callId!, {'type': answer.type, 'sdp': answer.sdp});
      if (mounted) setState(() {});
    } catch (e) {
      if (_callId != null) {
        unawaited(CallService.updateCallStatus(_callId!, 'ended'));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not connect the call.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await _disposeWebRtc();
    }
  }

  Future<void> _acceptCall() async {
    if (_callId == null) return;
    setState(() => _busy = true);
    await CallService.updateCallStatus(_callId!, 'connected');
    if (!mounted) return;
    setState(() {
      _status = 'connected';
      _busy = false;
      _callConnectedAt ??= DateTime.now();
    });
    unawaited(_startCalleeWebRtc());
  }

  Future<void> _declineCall() async {
    if (_callId == null) return;
    await CallService.declineCall(_callId!);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_callId != null) {
      int? durationSec;
      if (_callConnectedAt != null) {
        durationSec = DateTime.now().difference(_callConnectedAt!).inSeconds;
        if (durationSec < 0) durationSec = 0;
      }
      await CallService.updateCallStatus(
        _callId!,
        'ended',
        durationSeconds: durationSec,
      );
    }
    _callSub?.cancel();
    await _disposeWebRtc();
    if (mounted) Navigator.of(context).pop();
  }

  void _handleRemoteEnd({required bool declined}) {
    _callSub?.cancel();
    unawaited(_disposeWebRtc());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeWebRtc() async {
    _webrtcRunning = false;
    _remoteDescriptionSet = false;
    _callerAnswerApplied = false;
    _seenRemoteIceKeys.clear();
    _pendingRemoteIce.clear();

    try {
      _pc?.onIceCandidate = null;
      _pc?.onTrack = null;
      await _localStream?.dispose();
      _localStream = null;
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      await _localRenderer?.dispose();
      await _remoteRenderer?.dispose();
    } catch (_) {}
    _localRenderer = null;
    _remoteRenderer = null;
    _videoRenderersReady = false;
  }

  @override
  void dispose() {
    _callSub?.cancel();
    unawaited(_disposeWebRtc());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherName =
        widget.isIncoming ? (widget.callerName ?? 'Unknown') : (widget.calleeName ?? 'Unknown');
    final isVideo = widget.isVideo;

    return Scaffold(
      backgroundColor: AppTheme.darkSlate,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _status == 'ringing' || _status == 'connecting' ? _endCall : null,
        ),
      ),
      body: SafeArea(
        child: isVideo && _videoRenderersReady && _localRenderer != null && _remoteRenderer != null
            ? _buildVideoBody(otherName)
            : _buildAudioPlaceholderBody(otherName, isVideo),
      ),
    );
  }

  Widget _buildVideoBody(String otherName) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.black,
                child: RTCVideoView(
                  _remoteRenderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  placeholderBuilder: (_) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white54),
                        SizedBox(height: 16),
                        Text(
                          otherName,
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 16,
                width: 112,
                height: 148,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.grey.shade900,
                    child: RTCVideoView(
                      _localRenderer!,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                otherName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 12),
              Text(
                '· ${_statusText()}',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
        if (widget.isIncoming && _status == 'ringing')
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _actionButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: AppTheme.errorRed,
                  onPressed: _busy ? null : _declineCall,
                ),
                const SizedBox(width: 40),
                _actionButton(
                  icon: Icons.call,
                  label: 'Accept',
                  color: AppTheme.successGreen,
                  onPressed: _busy ? null : _acceptCall,
                ),
              ],
            ),
          )
        else if (!widget.isIncoming || _status == 'connected')
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: _actionButton(
              icon: Icons.call_end,
              label: 'End call',
              color: AppTheme.errorRed,
              onPressed: _busy ? null : _endCall,
            ),
          ),
      ],
    );
  }

  Widget _buildAudioPlaceholderBody(String otherName, bool isVideo) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            name: otherName,
            profilePhotoBase64: widget.otherPhotoBase64,
            photoUrl: widget.otherPhotoUrl,
            radius: 56,
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 24),
          Text(
            otherName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText(),
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          if (isVideo && !_videoRenderersReady) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
          ],
          const SizedBox(height: 32),
          if (widget.isIncoming && _status == 'ringing')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _actionButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: AppTheme.errorRed,
                  onPressed: _busy ? null : _declineCall,
                ),
                const SizedBox(width: 40),
                _actionButton(
                  icon: Icons.call,
                  label: 'Accept',
                  color: AppTheme.successGreen,
                  onPressed: _busy ? null : _acceptCall,
                ),
              ],
            )
          else if (!widget.isIncoming || _status == 'connected')
            _actionButton(
              icon: Icons.call_end,
              label: 'End call',
              color: AppTheme.errorRed,
              onPressed: _busy ? null : _endCall,
            ),
        ],
      ),
    );
  }

  String _statusText() {
    if (widget.isIncoming) {
      if (_status == 'ringing') return 'Incoming ${widget.isVideo ? "video" : "voice"} call';
      if (_status == 'connected') return _webrtcRunning ? 'Connected' : 'Connecting…';
    } else {
      if (_busy && _callId == null) return 'Starting call…';
      if (_status == 'ringing') return 'Calling…';
      if (_status == 'connected') return _webrtcRunning ? 'Connected' : 'Connecting…';
    }
    if (_status == 'ended' || _status == 'declined') return 'Call ended';
    return _status;
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }
}
