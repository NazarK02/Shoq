import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class CallScreen extends StatefulWidget {
  final String? callId;
  final String? peerId;
  final String? peerName;
  final String? peerPhotoUrl;
  final bool isVideo;
  final bool isIncoming;

  const CallScreen.outgoing({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
    this.isVideo = false,
  })  : callId = null,
        isIncoming = false;

  const CallScreen.incoming({
    super.key,
    required this.callId,
  })  : peerId = null,
        peerName = null,
        peerPhotoUrl = null,
        isVideo = false,
        isIncoming = true;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _CallPhase { ringing, connecting, inCall, ended }

class _CallScreenState extends State<CallScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteCandidatesSub;
  Timer? _ringTimeout;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isVideo = false;

  String? _callId;
  String _peerDisplayName = 'User';
  String? _peerPhotoUrl;
  _CallPhase _phase = _CallPhase.ringing;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    if (widget.isIncoming) {
      _initIncomingCall();
    } else {
      _initOutgoingCall();
    }
  }

  @override
  void dispose() {
    _ringTimeout?.cancel();
    _callDocSub?.cancel();
    _remoteCandidatesSub?.cancel();
    _cleanupRtc();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _initOutgoingCall() async {
    _isVideo = widget.isVideo;
    _peerDisplayName = widget.peerName ?? 'User';
    _peerPhotoUrl = widget.peerPhotoUrl;

    final allowed = await _ensurePermissions();
    if (!allowed) {
      if (mounted) Navigator.pop(context);
      return;
    }

    await _createPeerConnection();
    await _startLocalStream();

    setState(() => _phase = _CallPhase.ringing);

    final currentUser = _auth.currentUser;
    if (currentUser == null || widget.peerId == null) return;

    final callDoc = _firestore.collection('calls').doc();
    _callId = callDoc.id;

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await callDoc.set({
      'callerId': currentUser.uid,
      'calleeId': widget.peerId,
      'callerName': currentUser.displayName ?? 'User',
      'callerPhotoUrl': currentUser.photoURL ?? '',
      'isVideo': _isVideo,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      },
    });

    _listenForRemoteCandidates('calleeCandidates');
    _listenToCallDoc();

    _ringTimeout = Timer(const Duration(seconds: 35), () async {
      if (_phase != _CallPhase.ringing || _callId == null) return;
      await _updateCallStatus('missed');
      _endCallLocal();
    });
  }

  Future<void> _initIncomingCall() async {
    _callId = widget.callId;
    if (_callId == null) return;

    final doc = await _firestore.collection('calls').doc(_callId).get();
    if (!doc.exists || doc.data() == null) {
      _endCallLocal();
      return;
    }

    final data = doc.data()!;
    final status = data['status']?.toString() ?? '';
    if (status != 'ringing') {
      _endCallLocal();
      return;
    }

    _isVideo = data['isVideo'] == true;
    final callerName = data['callerName']?.toString();
    _peerDisplayName = callerName != null && callerName.trim().isNotEmpty
        ? callerName.trim()
        : 'User';
    final photo = data['callerPhotoUrl']?.toString();
    _peerPhotoUrl = photo != null && photo.trim().isNotEmpty ? photo : null;

    _listenToCallDoc();
    if (mounted) setState(() {});
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
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        }
      ],
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
      if (candidate.candidate == null || _callId == null) return;
      final collection = widget.isIncoming
          ? 'calleeCandidates'
          : 'callerCandidates';
      _firestore
          .collection('calls')
          .doc(_callId)
          .collection(collection)
          .add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'createdAt': FieldValue.serverTimestamp(),
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams.first;
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
      'audio': true,
      'video': _isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  void _listenToCallDoc() {
    if (_callId == null) return;
    _callDocSub?.cancel();
    _callDocSub = _firestore.collection('calls').doc(_callId).snapshots().listen(
      (snapshot) async {
        if (!snapshot.exists || snapshot.data() == null) {
          _endCallLocal();
          return;
        }

        final data = snapshot.data()!;
        final status = data['status']?.toString() ?? '';

        if (status == 'ended' ||
            status == 'declined' ||
            status == 'missed') {
          _endCallLocal();
          return;
        }

        if (!widget.isIncoming && data['answer'] != null) {
          final answer = data['answer'] as Map<String, dynamic>;
          if (!_remoteDescriptionSet) {
            await _setRemoteDescription(answer);
            if (mounted) setState(() => _phase = _CallPhase.inCall);
          }
        }
      },
    );
  }

  void _listenForRemoteCandidates(String collection) {
    if (_callId == null) return;
    _remoteCandidatesSub?.cancel();
    _remoteCandidatesSub = _firestore
        .collection('calls')
        .doc(_callId)
        .collection(collection)
        .snapshots()
        .listen((snapshot) async {
      for (final doc in snapshot.docChanges) {
        if (doc.type != DocumentChangeType.added) continue;
        final data = doc.doc.data();
        if (data == null) continue;
        final candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        if (_peerConnection == null) return;
        if (_remoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingRemoteCandidates.add(candidate);
        }
      }
    });
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

  Future<void> _answerCall() async {
    final allowed = await _ensurePermissions();
    if (!allowed) {
      await _declineCall();
      return;
    }

    if (_callId == null) return;

    await _createPeerConnection();
    await _startLocalStream();

    final callDoc = _firestore.collection('calls').doc(_callId);
    final snapshot = await callDoc.get();
    if (!snapshot.exists || snapshot.data() == null) {
      _endCallLocal();
      return;
    }

    final data = snapshot.data()!;
    final offer = data['offer'] as Map<String, dynamic>?;
    if (offer == null) {
      _endCallLocal();
      return;
    }

    await _setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await callDoc.update({
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
      'status': 'accepted',
    });

    _listenForRemoteCandidates('callerCandidates');
    if (mounted) setState(() => _phase = _CallPhase.inCall);
  }

  Future<void> _declineCall() async {
    await _updateCallStatus('declined');
    _endCallLocal();
  }

  Future<void> _hangUp() async {
    await _updateCallStatus('ended');
    _endCallLocal();
  }

  Future<void> _updateCallStatus(String status) async {
    if (_callId == null) return;
    await _firestore.collection('calls').doc(_callId).update({
      'status': status,
      'endedAt': FieldValue.serverTimestamp(),
    });
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
