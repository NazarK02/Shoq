import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/call_config.dart';
import '../services/chat_service_e2ee.dart';
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

  const CallScreen.outgoing({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
    this.isVideo = false,
  }) : invite = null,
       isIncoming = false;

  CallScreen.incoming({super.key, required CallInvite incomingInvite})
    : invite = incomingInvite,
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
  final ChatService _chatService = ChatService();

  // Only initialize video renderers for video calls
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<Map<String, dynamic>>? _signalSub;
  Timer? _ringTimeout;
  Timer? _offerRetry;
  Timer? _connectionTimeout;
  static const Duration _maxConnectionWait = Duration(seconds: 20);

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isVideo = false;
  bool _isInitializing = true;
  bool _renderersReady = false;

  int _offerRetryCount = 0;
  static const int _maxOfferRetries = 10;

  String? _callId;
  String? _selfId;
  String? _peerId;
  String _peerDisplayName = 'User';
  String? _peerPhotoUrl;
  String _callerName = 'User';
  String _callerPhotoUrl = '';
  Map<String, dynamic>? _remoteOffer;
  Map<String, dynamic>? _localOffer;
  _CallPhase _phase = _CallPhase.ringing;
  final DateTime _callOpenedAt = DateTime.now();
  DateTime? _callConnectedAt;
  String _callEndReason = 'ended';
  bool _callSummarySent = false;

  @override
  void initState() {
    super.initState();
    print(
      '🎬 CallScreen initState - isVideo: ${widget.isVideo}, isIncoming: ${widget.isIncoming}',
    );

    _isVideo = widget.isVideo;
    _peerId = widget.peerId;
    _peerDisplayName = widget.peerName ?? 'User';
    _peerPhotoUrl = widget.peerPhotoUrl;
    _remoteOffer = widget.invite?.offer;
    _callId = widget.invite?.callId;

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      print('Initializing renderers - isVideo: $_isVideo');

      // Only initialize renderers for video calls
      if (_isVideo) {
        _localRenderer = RTCVideoRenderer();
        _remoteRenderer = RTCVideoRenderer();

        await _localRenderer!.initialize();
        await _remoteRenderer!.initialize();
        print('Video renderers initialized');
      } else {
        print('Audio-only call - skipping video renderer initialization');
      }
    } catch (e, stack) {
      print('Renderer initialization error: $e');
      print('Stack trace: $stack');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize call: $e')),
        );
        Navigator.pop(context);
      }
      return;
    }

    if (!mounted) {
      print('Widget unmounted during initialization');
      return;
    }

    setState(() {
      _renderersReady = true;
      _isInitializing = false;
    });

    try {
      if (widget.isIncoming) {
        print('Initializing incoming call');
        await _initIncomingCall();
      } else {
        print('Initializing outgoing call');
        await _initOutgoingCall();
      }
    } catch (e, stack) {
      print('Initialization error: $e');
      print('Stack trace: $stack');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize call: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    print('🧹 CallScreen disposing');
    _ringTimeout?.cancel();
    _offerRetry?.cancel();
    _connectionTimeout?.cancel();
    _signalSub?.cancel();
    _cleanupRtc();
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  Future<void> _initOutgoingCall() async {
    print('📱 Starting outgoing call initialization');

    final allowed = await _ensurePermissions();
    if (!allowed) {
      print('❌ Permissions denied');
      if (mounted) Navigator.pop(context);
      return;
    }
    print('✅ Permissions granted');

    final currentUser = _auth.currentUser;
    if (currentUser == null || _peerId == null) {
      print('❌ No user or peerId');
      return;
    }

    // Prevent calling yourself
    if (_peerId == currentUser.uid) {
      print('❌ Cannot call yourself');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You cannot call yourself. Please test with another user.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    _selfId = currentUser.uid;
    _callerName = currentUser.displayName ?? 'User';
    _callerPhotoUrl = currentUser.photoURL ?? '';

    print('🔌 Connecting to signaling server');
    try {
      await _signaling.ensureConnected(userId: currentUser.uid);
    } catch (e) {
      print('❌ Failed to connect to signaling server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cannot connect to call server. '
              'Please check your internet connection and try again.\n'
              'Error: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    try {
      print('🔗 Creating peer connection');
      await _createPeerConnection();

      print('🎤 Starting local media stream');
      await _startLocalStream();

      print('✅ Local stream started successfully');
    } catch (e, stack) {
      print('❌ Error in call setup: $e');
      print('Stack trace: $stack');
      _endCallLocal();
      return;
    }

    if (mounted) setState(() => _phase = _CallPhase.ringing);

    _callId = '${currentUser.uid}_${DateTime.now().microsecondsSinceEpoch}';
    print('📱 Call ID: $_callId');

    _listenToSignaling();

    print('📝 Creating offer');
    final offer = await _peerConnection!.createOffer(_rtcOfferConstraints());
    await _peerConnection!.setLocalDescription(offer);
    _localOffer = {'sdp': offer.sdp, 'sdpType': offer.type};

    print('📤 Sending offer');
    await _sendOffer();
    _startOfferRetry();

    _ringTimeout = Timer(const Duration(seconds: 35), () async {
      print('⏰ Call timeout');
      if (_phase != _CallPhase.ringing || _callId == null) return;
      _callEndReason = 'missed';
      await _sendSignal('call_missed');
      _endCallLocal();
    });
  }

  Future<void> _initIncomingCall() async {
    print('📞 Initializing incoming call');

    final currentUser = _auth.currentUser;
    if (currentUser == null || _callId == null) {
      print('❌ No user or callId');
      return;
    }

    _selfId = currentUser.uid;
    await _signaling.ensureConnected(userId: currentUser.uid);
    _listenToSignaling();
    await NotificationService().clearCallNotification(_callId!);

    print('✅ Incoming call initialized');
  }

  Future<void> _listenToSignaling() async {
    _signalSub?.cancel();
    _signalSub = _signaling.messages.listen((message) async {
      if (message['callId']?.toString() != _callId) return;
      final type = message['type']?.toString();
      print('📨 Received signal: $type');

      if (type == 'call_answer') {
        final answer = {'sdp': message['sdp'], 'type': message['sdpType']};
        if (!_remoteDescriptionSet) {
          print('📥 Setting remote description (answer)');
          await _setRemoteDescription(answer);
          _offerRetry?.cancel();
          _ringTimeout?.cancel();
          _markCallConnected();
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
        _callEndReason = type == 'call_decline'
            ? 'declined'
            : (type == 'call_missed' ? 'missed' : 'ended');
        print('☎️ Call ended by peer: $type');
        if (_callId != null) {
          await NotificationService().clearCallNotification(_callId!);
        }
        _offerRetry?.cancel();
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
    print('🔐 Checking permissions - isVideo: $_isVideo');

    if (!Platform.isAndroid && !Platform.isIOS) {
      print('✅ Non-mobile platform, skipping permission check');
      return true;
    }

    final permissions = <Permission>[Permission.microphone];
    if (_isVideo) permissions.add(Permission.camera);

    print(
      '📋 Requesting permissions: ${permissions.map((p) => p.toString()).join(", ")}',
    );

    final results = await permissions.request();

    for (var entry in results.entries) {
      print('   ${entry.key}: ${entry.value}');
    }

    final granted = results.values.every((status) => status.isGranted);

    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission required for calls'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    return granted;
  }

  Future<void> _createPeerConnection() async {
    print('🔗 Creating RTCPeerConnection');

    // Clear any existing connection timeout and start a new one
    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(_maxConnectionWait, () {
      if (_phase != _CallPhase.inCall) {
        print('⏰ Connection timeout - call failed to establish');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call failed: Connection timeout'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _endCallLocal();
      }
    });

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
    print('✅ PeerConnection created');

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      print('🧊 ICE candidate generated');
      _sendSignal(
        'call_ice',
        data: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _peerConnection!.onTrack = (event) async {
      print('🎵 Remote track received: ${event.track.kind}');
      final track = event.track;
      MediaStream? stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = _remoteStream ?? await createLocalMediaStream('remote');
        final hasTrack = stream.getTracks().any((t) => t.id == track.id);
        if (!hasTrack) {
          stream.addTrack(track);
        }
      }

      _remoteStream = stream;
      if (_isVideo && track.kind == 'video' && _remoteRenderer != null) {
        _remoteRenderer!.srcObject = _remoteStream;
      }
      if (mounted) setState(() {});
    };

    _peerConnection!.onAddStream = (stream) {
      print('📺 Remote stream added');
      _remoteStream = stream;
      if (_isVideo && _remoteRenderer != null && _hasRemoteVideo()) {
        _remoteRenderer!.srcObject = _remoteStream;
      }
      if (mounted) setState(() {});
    };

    _peerConnection!.onConnectionState = (state) {
      print('🔗 Connection state: $state');

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('✅ Call connected!');
        _connectionTimeout?.cancel(); // Cancel timeout on successful connection
        _markCallConnected();
        if (mounted) setState(() => _phase = _CallPhase.inCall);
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        print('❌ Connection failed/disconnected: $state');
        if (_callConnectedAt == null) {
          _callEndReason = 'failed';
        }
        _connectionTimeout?.cancel();
        _endCallLocal();
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      print('ICE connection state: $state');
    };
  }

  Future<void> _startLocalStream() async {
    print('🎤 Getting user media - audio: true, video: $_isVideo');

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
      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      final audioTracks = _localStream!.getAudioTracks();
      final videoTracks = _localStream!.getVideoTracks();

      print(
        '✅ Got local stream - audio: ${audioTracks.length}, video: ${videoTracks.length}',
      );

      for (var track in audioTracks) {
        print('   Audio track: ${track.label} (enabled: ${track.enabled})');
      }
      for (var track in videoTracks) {
        print('   Video track: ${track.label} (enabled: ${track.enabled})');
      }
    } catch (e, stack) {
      print('❌ Failed to get media: $e');
      print('Stack trace: $stack');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to access ${_isVideo ? "camera/microphone" : "microphone"}: $e',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      rethrow;
    }

    if (_isVideo && _localRenderer != null) {
      _localRenderer!.srcObject = _localStream;
    }

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
      print('✅ Added track to peer connection: ${track.kind}');
    }

    if (Platform.isAndroid) {
      await Helper.setSpeakerphoneOn(_isVideo);
      _isSpeakerOn = _isVideo;
    }

    if (mounted) setState(() {});
  }

  Future<void> _setRemoteDescription(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    print('📥 Setting remote description');

    final description = RTCSessionDescription(data['sdp'], data['type']);
    await _peerConnection!.setRemoteDescription(description);
    _remoteDescriptionSet = true;

    print(
      '🧊 Adding ${_pendingRemoteCandidates.length} pending ICE candidates',
    );
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
    print('📞 Answering call');

    final allowed = await _ensurePermissions();
    if (!allowed) {
      print('❌ Permissions denied for answer');
      await _declineCall();
      return;
    }

    if (_remoteOffer == null) {
      print('❌ No remote offer available');
      _endCallLocal();
      return;
    }

    try {
      await _createPeerConnection();
      await _startLocalStream();
    } catch (e, stack) {
      print('❌ Error answering call: $e');
      print('Stack trace: $stack');
      _callEndReason = 'failed';
      _endCallLocal();
      return;
    }

    await _setRemoteDescription(_remoteOffer!);

    final answer = await _peerConnection!.createAnswer(_rtcOfferConstraints());
    await _peerConnection!.setLocalDescription(answer);

    await _sendSignal(
      'call_answer',
      data: {'sdp': answer.sdp, 'sdpType': answer.type},
    );

    _markCallConnected();
    await NotificationService().clearCallNotification(_callId!);
    if (mounted) setState(() => _phase = _CallPhase.inCall);

    print('✅ Call answered');
  }

  Future<void> _declineCall() async {
    print('❌ Declining call');
    _callEndReason = 'declined';
    await _sendSignal('call_decline');
    if (_callId != null) {
      await NotificationService().clearCallNotification(_callId!);
    }
    _endCallLocal();
  }

  Future<void> _hangUp() async {
    print('📵 Hanging up');
    _callEndReason = 'ended';
    await _sendSignal('call_end');
    if (_callId != null) {
      await NotificationService().clearCallNotification(_callId!);
    }
    _endCallLocal();
  }

  void _endCallLocal() {
    print('🛑 Ending call locally');
    unawaited(_sendCallSummaryMessage());
    if (!mounted) return;

    setState(() => _phase = _CallPhase.ended);
    _offerRetry?.cancel();
    _ringTimeout?.cancel();
    _cleanupRtc();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        print('👋 Popping call screen');
        Navigator.pop(context);
      }
    });
  }

  Future<void> _sendOffer() async {
    if (_callId == null ||
        _selfId == null ||
        _peerId == null ||
        _localOffer == null) {
      return;
    }

    await _signaling.send({
      'type': 'call_offer',
      'callId': _callId,
      'from': _selfId,
      'to': _peerId,
      'sdp': _localOffer!['sdp'],
      'sdpType': _localOffer!['sdpType'],
      'isVideo': _isVideo,
      'callerName': _callerName,
      'callerPhotoUrl': _callerPhotoUrl,
    });
  }

  void _startOfferRetry() {
    _offerRetry?.cancel();
    _offerRetryCount = 0;
    _offerRetry = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_phase != _CallPhase.ringing) {
        _offerRetry?.cancel();
        return;
      }

      _offerRetryCount++;
      print('🔄 Retrying offer (attempt $_offerRetryCount/$_maxOfferRetries)');

      if (_offerRetryCount >= _maxOfferRetries) {
        print('❌ Max retry attempts reached');
        _offerRetry?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call failed: No response from recipient'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _endCallLocal();
        return;
      }

      await _sendOffer();
    });
  }

  void _cleanupRtc() {
    print('🧹 Cleaning up RTC resources');

    for (final track in _localStream?.getTracks() ?? []) {
      track.stop();
    }
    _localRenderer?.srcObject = null;
    _remoteRenderer?.srcObject = null;
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
  }

  void _markCallConnected() {
    _callConnectedAt ??= DateTime.now();
    _callEndReason = 'ended';
  }

  String _formatDuration(Duration duration) {
    var seconds = duration.inSeconds;
    if (seconds < 0) seconds = 0;

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  String _buildCallSummaryText({
    required DateTime startedAt,
    required bool wasAccepted,
    required Duration duration,
  }) {
    final callType = _isVideo ? 'Video call' : 'Audio call';
    final when = DateFormat('MMM d, HH:mm').format(startedAt);

    if (wasAccepted) {
      return '$callType accepted at $when - Duration ${_formatDuration(duration)}';
    }

    switch (_callEndReason) {
      case 'declined':
        return '$callType declined at $when';
      case 'missed':
        return '$callType missed at $when';
      case 'failed':
        return '$callType failed at $when';
      default:
        return '$callType ended at $when';
    }
  }

  Future<void> _sendCallSummaryMessage() async {
    if (_callSummarySent) return;
    _callSummarySent = true;

    try {
      // Only caller writes summary to avoid duplicate log entries.
      if (widget.isIncoming) return;

      final currentUser = _auth.currentUser;
      final peerId = _peerId;
      if (currentUser == null || peerId == null || peerId.trim().isEmpty) {
        return;
      }

      final endedAt = DateTime.now();
      final startedAt = _callConnectedAt ?? _callOpenedAt;
      final wasAccepted = _callConnectedAt != null;
      final duration = wasAccepted
          ? endedAt.difference(_callConnectedAt!)
          : Duration.zero;

      final summaryText = _buildCallSummaryText(
        startedAt: startedAt,
        wasAccepted: wasAccepted,
        duration: duration,
      );

      await _chatService.initializeEncryption();
      final conversationId = await _chatService.initializeConversation(peerId);
      if (conversationId == null) return;

      await _chatService.sendMessage(
        conversationId: conversationId,
        messageText: summaryText,
        recipientId: peerId,
      );
    } catch (e) {
      print('Failed to send call summary message: $e');
    }
  }

  void _toggleMute() {
    _isMuted = !_isMuted;
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !_isMuted;
    }
    print('🎤 Mute: $_isMuted');
    if (mounted) setState(() {});
  }

  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    if (Platform.isAndroid) {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
    print('🔊 Speaker: $_isSpeakerOn');
    if (mounted) setState(() {});
  }

  void _toggleCamera() {
    _isCameraOff = !_isCameraOff;
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = !_isCameraOff;
    }
    print('📹 Camera off: $_isCameraOff');
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (!_isVideo) return;
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    print('🔄 Camera switched');
  }

  String _statusText() {
    switch (_phase) {
      case _CallPhase.ringing:
        if (widget.isIncoming) {
          return 'Incoming call';
        } else {
          if (_offerRetryCount > 0) {
            return 'Connecting... (attempt $_offerRetryCount)';
          }
          return 'Calling...';
        }
      case _CallPhase.connecting:
        return 'Connecting...';
      case _CallPhase.inCall:
        return 'In call';
      case _CallPhase.ended:
        return 'Call ended';
    }
  }

  bool _hasRemoteVideo() {
    if (!_isVideo || _remoteStream == null) return false;
    final tracks = _remoteStream!.getVideoTracks();
    return tracks.isNotEmpty && tracks.any((t) => t.enabled);
  }

  Widget _buildAvatar() {
    if (_peerPhotoUrl == null || _peerPhotoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 56,
        backgroundColor: Colors.grey[800],
        child: const Icon(Icons.person, size: 64, color: Colors.white70),
      );
    }

    return CircleAvatar(
      radius: 56,
      backgroundImage: NetworkImage(_peerPhotoUrl!),
      backgroundColor: Colors.grey[800],
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      color: const Color(0xFF1a1a1a),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Text(
              'Initializing ${_isVideo ? 'video' : 'audio'} call...',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteView() {
    // For video calls with active remote stream
    if (_isVideo &&
        _remoteRenderer != null &&
        _remoteRenderer!.srcObject != null &&
        _hasRemoteVideo()) {
      return RTCVideoView(
        _remoteRenderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    // For audio calls or video calls without remote stream yet
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1a1a1a), const Color(0xFF2d2d2d)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(),
            const SizedBox(height: 24),
            Text(
              _peerDisplayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _statusText(),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPreview() {
    if (!_isVideo ||
        _localRenderer == null ||
        _localRenderer!.srcObject == null) {
      return const Positioned.fill(child: SizedBox.shrink());
    }

    return Positioned(
      top: 24,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 110,
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: RTCVideoView(
            _localRenderer!,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    if (widget.isIncoming && _phase == _CallPhase.ringing) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCircleButton(
              icon: Icons.call_end,
              color: Colors.red,
              label: 'Decline',
              onPressed: _declineCall,
            ),
            _buildCircleButton(
              icon: Icons.call,
              color: Colors.green,
              label: 'Accept',
              onPressed: _answerCall,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.7), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircleButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            color: _isMuted ? Colors.red : Colors.white24,
            onPressed: _toggleMute,
          ),
          if (_isVideo)
            _buildCircleButton(
              icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
              color: _isCameraOff ? Colors.red : Colors.white24,
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
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? label,
  }) {
    final button = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 28),
        onPressed: onPressed,
      ),
    );

    if (label != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return button;
  }

  @override
  Widget build(BuildContext context) {
    final needsRenderers = _isVideo;
    if (_isInitializing || (needsRenderers && !_renderersReady)) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a1a),
        body: SafeArea(child: _buildLoadingIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildRemoteView()),
            _buildLocalPreview(),
            Positioned(left: 0, right: 0, bottom: 0, child: _buildControls()),
          ],
        ),
      ),
    );
  }
}
