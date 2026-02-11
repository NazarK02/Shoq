import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/call_config.dart';
import '../services/notification_service.dart';
import '../services/signaling_service.dart';

class CallInvite {
  final String callId;
  final String fromId;
  final String callerName;
  final String? callerPhotoUrl;
  final bool isVideo;
  final Map<String, dynamic> offer;

  const CallInvite({
    required this.callId,
    required this.fromId,
    required this.callerName,
    required this.callerPhotoUrl,
    required this.isVideo,
    required this.offer,
  });
}

class CallScreen extends StatefulWidget {
  final CallInvite? invite;
  final String? peerId;
  final String? peerName;
  final String? peerPhotoUrl;
  final bool isVideo;
  final bool isIncoming;

  CallScreen.outgoing({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
    this.isVideo = false,
  })  : invite = null,
        isIncoming = false;

  CallScreen.incoming({
    super.key,
    required CallInvite incomingInvite,
  })  : invite = incomingInvite,
        peerId = incomingInvite.fromId,
        peerName = incomingInvite.callerName,
        peerPhotoUrl = incomingInvite.callerPhotoUrl,
        isVideo = incomingInvite.isVideo,
        isIncoming = true;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _CallPhase { ringing, connecting, inCall, ended }

class _CallScreenState extends State<CallScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SignalingService _signaling = SignalingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<Map<String, dynamic>>? _signalSub;
  Timer? _ringTimeout;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isVideo = false;

  String? _callId;
  String? _selfId;
  String? _peerId;
  String _peerDisplayName = 'User';
  String? _peerPhotoUrl;
  Map<String, dynamic>? _remoteOffer;
  _CallPhase _phase = _CallPhase.ringing;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    _isVideo = widget.isVideo;
    _peerId = widget.peerId;
    _peerDisplayName = widget.peerName ?? 'User';
    _peerPhotoUrl = widget.peerPhotoUrl;
    _remoteOffer = widget.invite?.offer;
    _callId = widget.invite?.callId;

    if (widget.isIncoming) {
      _initIncomingCall();
    } else {
      _initOutgoingCall();
    }
  }

  @override
  void dispose() {
    _ringTimeout?.cancel();
    _signalSub?.cancel();
    _cleanupRtc();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _initOutgoingCall() async {
    final allowed = await _ensurePermissions();
    if (!allowed) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null || _peerId == null) return;
    _selfId = currentUser.uid;
    await _signaling.ensureConnected(userId: currentUser.uid);

    try {
      await _createPeerConnection();
      await _startLocalStream();
    } catch (_) {
      _endCallLocal();
      return;
    }

    setState(() => _phase = _CallPhase.ringing);

    _callId = '${currentUser.uid}_${DateTime.now().microsecondsSinceEpoch}';

    final offer = await _peerConnection!.createOffer(_rtcOfferConstraints());
    await _peerConnection!.setLocalDescription(offer);

    await _signaling.send({
      'type': 'call_offer',
      'callId': _callId,
      'from': currentUser.uid,
      'to': _peerId,
      'sdp': offer.sdp,
      'sdpType': offer.type,
      'isVideo': _isVideo,
      'callerName': currentUser.displayName ?? 'User',
      'callerPhotoUrl': currentUser.photoURL ?? '',
    });

    _listenToSignaling();

    _ringTimeout = Timer(const Duration(seconds: 35), () async {
      if (_phase != _CallPhase.ringing || _callId == null) return;
      await _sendSignal('call_missed');
      _endCallLocal();
    });
  }

  Future<void> _initIncomingCall() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || _callId == null) return;
    _selfId = currentUser.uid;
    await _signaling.ensureConnected(userId: currentUser.uid);
    _listenToSignaling();
    await NotificationService().clearCallNotification(_callId!);
    if (mounted) setState(() {});
  }

  Future<void> _listenToSignaling() async {
    _signalSub?.cancel();
    _signalSub = _signaling.messages.listen((message) async {
      if (message['callId']?.toString() != _callId) return;
      final type = message['type']?.toString();

      if (type == 'call_answer') {
        final answer = {
          'sdp': message['sdp'],
          'type': message['sdpType'],
        };
        if (!_remoteDescriptionSet) {
          await _setRemoteDescription(answer);
          _ringTimeout?.cancel();
          if (mounted) setState(() => _phase = _CallPhase.inCall);
        }
        return;
      }

      if (type == 'call_ice') {
        final candidate = RTCIceCandidate(
          message['candidate'],
          message['sdpMid'],
          message['sdpMLineIndex'],
        );
        if (_peerConnection == null) return;
        if (_remoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingRemoteCandidates.add(candidate);
        }
        return;
      }

      if (type == 'call_end' ||
          type == 'call_decline' ||
          type == 'call_missed') {
        if (_callId != null) {
          await NotificationService().clearCallNotification(_callId!);
        }
        _endCallLocal();
        return;
      }
    });
  }

  Future<void> _sendSignal(String type, {Map<String, dynamic>? data}) async {
    if (_callId == null || _selfId == null || _peerId == null) return;
    await _signaling.send({
      'type': type,
      'callId': _callId,
      'from': _selfId,
      'to': _peerId,
      ...?data,
    });
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    final permissions = <Permission>[Permission.microphone];
    if (_isVideo) permissions.add(Permission.camera);

    final results = await permissions.request();
    final granted = results.values.every((status) => status.isGranted);

    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions required for calling')),
      );
    }

    return granted;
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': CallConfig.iceServers,
      'sdpSemantics': 'unified-plan',
    };

    final constraints = {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    _peerConnection = await createPeerConnection(config, constraints);

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _sendSignal('call_ice', data: {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onTrack = (event) async {
      MediaStream? stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = _remoteStream ?? await createLocalMediaStream('remote');
        stream.addTrack(event.track);
      }

      _remoteStream = stream;
      _remoteRenderer.srcObject = _remoteStream;
      if (mounted) setState(() {});
    };

    _peerConnection!.onAddStream = (stream) {
      _remoteStream = stream;
      _remoteRenderer.srcObject = _remoteStream;
      if (mounted) setState(() {});
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          mounted) {
        setState(() => _phase = _CallPhase.inCall);
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _endCallLocal();
      }
    };
  }

  Future<void> _startLocalStream() async {
    final mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': _isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to access media devices: $e')),
        );
      }
      rethrow;
    }

    _localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    if (Platform.isAndroid) {
      await Helper.setSpeakerphoneOn(_isVideo);
    }
  }

  Future<void> _setRemoteDescription(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    final description = RTCSessionDescription(
      data['sdp'],
      data['type'],
    );
    await _peerConnection!.setRemoteDescription(description);
    _remoteDescriptionSet = true;

    for (final candidate in _pendingRemoteCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Map<String, dynamic> _rtcOfferConstraints() {
    return {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': _isVideo,
      },
      'optional': [],
    };
  }

  Future<void> _answerCall() async {
    final allowed = await _ensurePermissions();
    if (!allowed) {
      await _declineCall();
      return;
    }

    if (_remoteOffer == null) {
      _endCallLocal();
      return;
    }

    try {
      await _createPeerConnection();
      await _startLocalStream();
    } catch (_) {
      _endCallLocal();
      return;
    }

    await _setRemoteDescription(_remoteOffer!);

    final answer = await _peerConnection!.createAnswer(_rtcOfferConstraints());
    await _peerConnection!.setLocalDescription(answer);

    await _sendSignal('call_answer', data: {
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });

    await NotificationService().clearCallNotification(_callId!);
    if (mounted) setState(() => _phase = _CallPhase.inCall);
  }

  Future<void> _declineCall() async {
    await _sendSignal('call_decline');
    if (_callId != null) {
      await NotificationService().clearCallNotification(_callId!);
    }
    _endCallLocal();
  }

  Future<void> _hangUp() async {
    await _sendSignal('call_end');
    if (_callId != null) {
      await NotificationService().clearCallNotification(_callId!);
    }
    _endCallLocal();
  }

  void _endCallLocal() {
    if (!mounted) return;
    setState(() => _phase = _CallPhase.ended);
    _cleanupRtc();
    Navigator.pop(context);
  }

  void _cleanupRtc() {
    for (final track in _localStream?.getTracks() ?? []) {
      track.stop();
    }
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
  }

  void _toggleMute() {
    _isMuted = !_isMuted;
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !_isMuted;
    }
    if (mounted) setState(() {});
  }

  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    if (Platform.isAndroid) {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
    if (mounted) setState(() {});
  }

  void _toggleCamera() {
    _isCameraOff = !_isCameraOff;
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = !_isCameraOff;
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (!_isVideo) return;
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  String _statusText() {
    switch (_phase) {
      case _CallPhase.ringing:
        return widget.isIncoming ? 'Incoming call' : 'Calling...';
      case _CallPhase.connecting:
        return 'Connecting...';
      case _CallPhase.inCall:
        return 'In call';
      case _CallPhase.ended:
        return 'Call ended';
    }
  }

  Widget _buildAvatar() {
    if (_peerPhotoUrl == null || _peerPhotoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Colors.grey[300],
        child: const Icon(Icons.person, size: 48, color: Colors.grey),
      );
    }

    return CircleAvatar(
      radius: 48,
      backgroundImage: NetworkImage(_peerPhotoUrl!),
      backgroundColor: Colors.grey[300],
    );
  }

  Widget _buildRemoteView() {
    if (_isVideo && _remoteRenderer.srcObject != null) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(),
            const SizedBox(height: 16),
            Text(
              _peerDisplayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText(),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPreview() {
    if (!_isVideo || _localRenderer.srcObject == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 24,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 110,
          height: 150,
          child: RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    if (widget.isIncoming && _phase == _CallPhase.ringing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircleButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: _declineCall,
          ),
          _buildCircleButton(
            icon: Icons.call,
            color: Colors.green,
            onPressed: _answerCall,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircleButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          color: Colors.white24,
          onPressed: _toggleMute,
        ),
        if (_isVideo)
          _buildCircleButton(
            icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
            color: Colors.white24,
            onPressed: _toggleCamera,
          ),
        if (_isVideo)
          _buildCircleButton(
            icon: Icons.cameraswitch,
            color: Colors.white24,
            onPressed: _switchCamera,
          ),
        _buildCircleButton(
          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          color: Colors.white24,
          onPressed: _toggleSpeaker,
        ),
        _buildCircleButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: _hangUp,
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: color,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildRemoteView()),
            _buildLocalPreview(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }
}
