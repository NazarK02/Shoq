import 'dart:async';
import 'dart:io';
import '../services/firestore_streams.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'home_screen.dart';
import '../services/active_session_service.dart';
import '../services/call_config.dart';
import '../services/signaling_service.dart';
import '../services/theme_service.dart';
import '../widgets/chat_message_text.dart';

class VoiceChannelScreen extends StatefulWidget {
  final String conversationId;
  final String conversationTitle;
  final String channelId;
  final String channelName;

  const VoiceChannelScreen({
    super.key,
    required this.conversationId,
    required this.conversationTitle,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<VoiceChannelScreen> createState() => _VoiceChannelScreenState();
}

class _VoiceChannelScreenState extends State<VoiceChannelScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SignalingService _signaling = SignalingService();
  late final String _sessionId;

  StreamSubscription<Map<String, dynamic>>? _signalSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;
  Timer? _presenceHeartbeat;
  Timer? _connectionHealthTimer;

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, bool> _remoteDescriptionSet = {};
  final Map<String, String> _peerClientIds = {};
  Map<String, _VoiceMember> _members = const {};

  bool _isInitializing = true;
  bool _isJoining = false;
  bool _isLeaving = false;
  bool _joinedPresence = false;
  bool _isMuted = false;
  bool _isDeafened = false;
  bool _speakerOn = false;
  String? _error;
  bool _isSendingVoiceText = false;

  String? _selfUid;
  String _sessionKey = '';
  final TextEditingController _voiceChatController = TextEditingController();

  DocumentReference<Map<String, dynamic>> get _voiceDocRef => _firestore
      .collection('conversations')
      .doc(widget.conversationId)
      .collection('voiceChannels')
      .doc(widget.channelId);

  CollectionReference<Map<String, dynamic>> get _voiceMessagesRef =>
      _voiceDocRef.collection('messages');

  @override
  void initState() {
    super.initState();
    _sessionId = 'voice_${widget.conversationId}_${widget.channelId}';
    ActiveSessionService().setVoiceSession(
      sessionId: _sessionId,
      conversationTitle: widget.conversationTitle,
      channelName: widget.channelName,
    );
    unawaited(_initializeVoiceChannel());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ActiveSessionService().bindRoute(context, sessionId: _sessionId);
  }

  Future<void> _initializeVoiceChannel() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'You must be logged in to join voice chat.';
      });
      return;
    }

    _selfUid = user.uid;
    _sessionKey = '${widget.conversationId}_${widget.channelId}';

    try {
      final allowed = await _ensureMicrophonePermission();
      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _isInitializing = false;
          _error = 'Microphone permission is required for voice channels.';
        });
        return;
      }

      await _signaling.ensureConnected(userId: user.uid);
      await _startLocalAudio();
      await _verifyMembership(user.uid);
      await _joinPresence(user);
      if (mounted) {
        setState(() {
          _members = _mergeSelfMember(_members);
        });
      }
      await _refreshPresenceFromServer();

      _listenToPresence();
      _listenToSignaling();
      _startPresenceHeartbeat();
      _startConnectionHealthChecks();

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code.trim().toLowerCase();
      final message = code == 'permission-denied'
          ? 'You do not have permission to join this voice channel.'
          : 'Could not join voice channel: ${e.message ?? e.code}';
      setState(() {
        _isInitializing = false;
        _error = message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'Could not join voice channel: $e';
      });
    }
  }

  Future<void> _verifyMembership(String uid) async {
    final conversationRef = _firestore
        .collection('conversations')
        .doc(widget.conversationId);
    final snapshot = await conversationRef.get();
    if (!snapshot.exists) {
      throw Exception('Conversation not found.');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final rawParticipants = data['participants'];
    final participants = rawParticipants is List
        ? rawParticipants
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet()
        : const <String>{};
    if (!participants.contains(uid)) {
      throw Exception('Your account is not a participant of this server.');
    }
  }

  Future<bool> _ensureMicrophonePermission() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return true;
    }
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startLocalAudio() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    _localStream = stream;
  }

  Future<void> _joinPresence(User user) async {
    if (_isJoining) return;
    _isJoining = true;
    try {
      final memberPath = 'activeMembers.${user.uid}';
      await _voiceDocRef.set({
        '$memberPath.userId': user.uid,
        '$memberPath.clientId': _signaling.clientId,
        '$memberPath.displayName': user.displayName ?? 'User',
        '$memberPath.photoUrl': user.photoURL ?? '',
        '$memberPath.muted': _isMuted,
        '$memberPath.updatedAt': FieldValue.serverTimestamp(),
        '$memberPath.joinedAt': FieldValue.serverTimestamp(),
        'sessionKey': _sessionKey,
        'conversationId': widget.conversationId,
        'channelId': widget.channelId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _joinedPresence = true;
    } finally {
      _isJoining = false;
    }
  }

  void _startPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    // Send heartbeat every 8 seconds to ensure members stay visible
    _presenceHeartbeat = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_updatePresenceHeartbeat());
    });
  }

  void _startConnectionHealthChecks() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_runConnectionHealthCheck());
    });
  }

  bool _isPeerConnected(String userId) {
    final pc = _peerConnections[userId];
    if (pc == null) return false;
    return pc.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  }

  Future<void> _runConnectionHealthCheck() async {
    try {
      if (_isLeaving) return;
      if (_members.isEmpty) return;

      for (final member in _members.values) {
        if (member.userId == _selfUid) continue;
        final clientId = member.clientId.trim();
        if (clientId.isEmpty || clientId == _signaling.clientId) continue;

        final currentClientId = _peerClientIds[member.userId];
        if (currentClientId != null && currentClientId != clientId) {
          await _closePeerConnection(member.userId);
        }

        _peerClientIds[member.userId] = clientId;
        if (!_peerConnections.containsKey(member.userId)) {
          await _createPeerConnection(member);
        }

        if (_shouldInitiateFor(member) && !_isPeerConnected(member.userId)) {
          await _sendVoiceOffer(member.userId);
        }
      }
    } catch (e) {
      debugPrint('Voice health check failed: $e');
    }
  }

  Future<void> _updatePresenceHeartbeat() async {
    final uid = _selfUid;
    if (!_joinedPresence || uid == null || uid.isEmpty) return;
    final memberPath = 'activeMembers.$uid';
    try {
      await _voiceDocRef.set({
        '$memberPath.clientId': _signaling.clientId,
        '$memberPath.muted': _isMuted,
        '$memberPath.updatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Voice heartbeat failed: $e');
    }
  }

  void _listenToPresence() {
    _presenceSub?.cancel();
    _presenceSub = _voiceDocRef.safeSnapshots().listen(
      (snapshot) async {
        final data = snapshot.data();
        if (data == null) {
          if (mounted) {
            setState(() {
              _members = const {};
            });
          }
          await _syncPeerConnections(const {});
          return;
        }

        final parsed = _mergeSelfMember(_parseMembers(data['activeMembers']));
        if (mounted) {
          setState(() {
            _members = parsed;
          });
        }
        await _syncPeerConnections(parsed);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        final text = error.toString().trim();
        final message = text.toLowerCase().contains('permission-denied')
            ? 'Voice presence read is blocked by Firestore rules.'
            : 'Voice presence stream failed: $text';
        setState(() {
          _error = message;
        });
      },
    );
  }

  Future<void> _refreshPresenceFromServer() async {
    try {
      final snapshot =
          await _voiceDocRef.get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data == null) return;
      final parsed = _mergeSelfMember(_parseMembers(data['activeMembers']));
      if (!mounted) return;
      setState(() {
        _members = parsed;
      });
      await _syncPeerConnections(parsed);
    } catch (e) {
      debugPrint('Voice presence refresh failed: $e');
    }
  }

  Map<String, _VoiceMember> _parseMembers(dynamic raw) {
    if (raw is! Map) return const {};
    final now = DateTime.now();
    final result = <String, _VoiceMember>{};
    raw.forEach((key, value) {
      final userId = key.toString().trim();
      if (userId.isEmpty || value is! Map) return;
      final member = _VoiceMember.fromMap(
        userId: userId,
        data: Map<String, dynamic>.from(value),
      );
      final seenAt = member.updatedAt?.toDate() ?? member.joinedAt?.toDate();
      // Increased timeout from 40 to 70 seconds to accommodate network delays
      if (seenAt != null &&
          now.difference(seenAt) > const Duration(seconds: 70)) {
        debugPrint('Voice: Removing stale member $userId (seen ${now.difference(seenAt).inSeconds}s ago)');
        return;
      }
      result[userId] = member;
    });
    debugPrint('Voice: Parsed ${result.length} active members');
    return result;
  }

  _VoiceMember? _buildSelfMember() {
    final user = _auth.currentUser;
    final uid = _selfUid;
    if (user == null || uid == null || uid.isEmpty) return null;
    return _VoiceMember(
      userId: uid,
      clientId: _signaling.clientId,
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'You',
      photoUrl: user.photoURL ?? '',
      muted: _isMuted,
      joinedAt: null,
      updatedAt: null,
    );
  }

  Map<String, _VoiceMember> _mergeSelfMember(
    Map<String, _VoiceMember> members,
  ) {
    final uid = _selfUid;
    if (uid == null || uid.isEmpty || !_joinedPresence) return members;
    if (members.containsKey(uid)) return members;
    final selfMember = _buildSelfMember();
    if (selfMember == null) return members;
    return <String, _VoiceMember>{...members, uid: selfMember};
  }

  Future<void> _syncPeerConnections(Map<String, _VoiceMember> members) async {
    final uid = _selfUid;
    if (uid == null || uid.isEmpty) return;

    final targets = members.values
        .where(
          (member) =>
              member.userId != uid &&
              member.clientId.trim().isNotEmpty &&
              member.clientId != _signaling.clientId,
        )
        .toList();
    final targetUserIds = targets.map((member) => member.userId).toSet();

    for (final member in targets) {
      final existingClientId = _peerClientIds[member.userId];
      if (existingClientId != null && existingClientId != member.clientId) {
        await _closePeerConnection(member.userId);
      }

      _peerClientIds[member.userId] = member.clientId;
      if (!_peerConnections.containsKey(member.userId)) {
        await _createPeerConnection(member);
        if (_shouldInitiateFor(member)) {
          await _sendVoiceOffer(member.userId);
        }
      }
    }

    final stalePeers = _peerConnections.keys
        .where((peerUserId) => !targetUserIds.contains(peerUserId))
        .toList();
    for (final peerUserId in stalePeers) {
      await _closePeerConnection(peerUserId);
    }
  }

  bool _shouldInitiateFor(_VoiceMember member) {
    return _signaling.clientId.compareTo(member.clientId) > 0;
  }

  Future<void> _createPeerConnection(_VoiceMember member) async {
    final config = <String, dynamic>{
      'iceServers': CallConfig.iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    final pc = await createPeerConnection(config);
    final local = _localStream;
    if (local != null) {
      for (final track in local.getAudioTracks()) {
        await pc.addTrack(track, local);
      }
    }

    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind != 'audio') return;
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        if (_isDeafened) {
          for (final track in stream.getAudioTracks()) {
            track.enabled = false;
          }
        }
        if (!mounted) return;
        setState(() {
          _remoteStreams[member.userId] = stream;
        });
        return;
      }

      unawaited(() async {
        final existing = _remoteStreams[member.userId];
        final stream =
            existing ?? await createLocalMediaStream('remote_${member.userId}');
        final hasTrack = stream.getTracks().any((t) => t.id == event.track.id);
        if (!hasTrack) {
          stream.addTrack(event.track);
        }
        if (_isDeafened) {
          for (final track in stream.getAudioTracks()) {
            track.enabled = false;
          }
        }
        if (!mounted) return;
        setState(() {
          _remoteStreams[member.userId] = stream;
        });
      }());
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      unawaited(
        _sendSignal(
          type: 'voice_ice',
          toUserId: member.userId,
          toClientId: member.clientId,
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      final latestMember = _members[member.userId];
      if (latestMember == null) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_shouldInitiateFor(latestMember)) {
          unawaited(_sendVoiceOffer(latestMember.userId));
        }
      }
      if (mounted) setState(() {});
    };

    _peerConnections[member.userId] = pc;
    _pendingCandidates[member.userId] = <RTCIceCandidate>[];
    _remoteDescriptionSet[member.userId] = false;
  }

  Future<void> _sendVoiceOffer(String peerUserId) async {
    final pc = _peerConnections[peerUserId];
    final peerClientId = _peerClientIds[peerUserId];
    if (pc == null || peerClientId == null || peerClientId.isEmpty) return;

    try {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
        'voiceActivityDetection': true,
      });
      await pc.setLocalDescription(offer);

      await _sendSignal(
        type: 'voice_offer',
        toUserId: peerUserId,
        toClientId: peerClientId,
        data: {'sdp': offer.sdp, 'sdpType': offer.type},
      );
    } catch (e) {
      debugPrint('Voice offer failed for $peerUserId: $e');
    }
  }

  void _listenToSignaling() {
    _signalSub?.cancel();
    _signalSub = _signaling.messages.listen((message) async {
      try {
        if (_isLeaving) return;
        final type = message['type']?.toString().trim() ?? '';
        if (type.isEmpty || !type.startsWith('voice_')) return;
        if (message['sessionKey']?.toString().trim() != _sessionKey) return;
        if (message['channelId']?.toString().trim() != widget.channelId) {
          return;
        }

        final uid = _selfUid;
        if (uid == null || uid.isEmpty) return;
        final to = message['to']?.toString().trim() ?? '';
        if (to.isNotEmpty && to != uid) return;
        final toClientId = message['toClientId']?.toString().trim() ?? '';
        if (toClientId.isNotEmpty && toClientId != _signaling.clientId) {
          return;
        }

        final fromUserId = message['from']?.toString().trim() ?? '';
        if (fromUserId.isEmpty || fromUserId == uid) return;
        final fromClientId = message['fromClientId']?.toString().trim() ?? '';

        if (type == 'voice_offer') {
          await _handleVoiceOffer(
            fromUserId: fromUserId,
            fromClientId: fromClientId,
            sdp: message['sdp']?.toString() ?? '',
            sdpType: message['sdpType']?.toString() ?? 'offer',
            fromDisplayName: message['fromDisplayName']?.toString(),
            fromPhotoUrl: message['fromPhotoUrl']?.toString(),
          );
          return;
        }

        if (type == 'voice_answer') {
          await _handleVoiceAnswer(
            fromUserId: fromUserId,
            sdp: message['sdp']?.toString() ?? '',
            sdpType: message['sdpType']?.toString() ?? 'answer',
          );
          return;
        }

        if (type == 'voice_ice') {
          await _handleVoiceIce(
            fromUserId: fromUserId,
            candidate: message['candidate']?.toString() ?? '',
            sdpMid: message['sdpMid']?.toString(),
            sdpMLineIndex: (message['sdpMLineIndex'] is num)
                ? (message['sdpMLineIndex'] as num).toInt()
                : int.tryParse(message['sdpMLineIndex']?.toString() ?? ''),
          );
          return;
        }

        if (type == 'voice_leave') {
          await _closePeerConnection(fromUserId);
        }
      } catch (e) {
        debugPrint('Voice signaling handler failed: $e');
      }
    });
  }

  Future<void> _handleVoiceOffer({
    required String fromUserId,
    required String fromClientId,
    required String sdp,
    required String sdpType,
    String? fromDisplayName,
    String? fromPhotoUrl,
  }) async {
    if (sdp.trim().isEmpty) return;

    final known = _members[fromUserId];
    final member =
        known ??
        _VoiceMember(
          userId: fromUserId,
          clientId: fromClientId,
          displayName: fromDisplayName?.trim().isNotEmpty == true
              ? fromDisplayName!.trim()
              : 'Member',
          photoUrl: fromPhotoUrl?.trim() ?? '',
          muted: false,
          joinedAt: null,
          updatedAt: null,
        );

    if (_peerClientIds[fromUserId] != member.clientId) {
      await _closePeerConnection(fromUserId);
      _peerClientIds[fromUserId] = member.clientId;
    }

    if (!_peerConnections.containsKey(fromUserId)) {
      await _createPeerConnection(member);
    }
    final pc = _peerConnections[fromUserId];
    if (pc == null) return;

    final remoteDesc = RTCSessionDescription(sdp, sdpType);
    await pc.setRemoteDescription(remoteDesc);
    _remoteDescriptionSet[fromUserId] = true;
    await _flushPendingCandidates(fromUserId);

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
      'voiceActivityDetection': true,
    });
    await pc.setLocalDescription(answer);
    await _sendSignal(
      type: 'voice_answer',
      toUserId: fromUserId,
      toClientId: fromClientId,
      data: {'sdp': answer.sdp, 'sdpType': answer.type},
    );
  }

  Future<void> _handleVoiceAnswer({
    required String fromUserId,
    required String sdp,
    required String sdpType,
  }) async {
    if (sdp.trim().isEmpty) return;
    final pc = _peerConnections[fromUserId];
    if (pc == null) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
    _remoteDescriptionSet[fromUserId] = true;
    await _flushPendingCandidates(fromUserId);
  }

  Future<void> _handleVoiceIce({
    required String fromUserId,
    required String candidate,
    required String? sdpMid,
    required int? sdpMLineIndex,
  }) async {
    if (candidate.trim().isEmpty) return;
    final pc = _peerConnections[fromUserId];
    if (pc == null) return;

    final ice = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
    if (_remoteDescriptionSet[fromUserId] == true) {
      await pc.addCandidate(ice);
      return;
    }
    _pendingCandidates
        .putIfAbsent(fromUserId, () => <RTCIceCandidate>[])
        .add(ice);
  }

  Future<void> _flushPendingCandidates(String peerUserId) async {
    final pc = _peerConnections[peerUserId];
    if (pc == null) return;
    final queue = _pendingCandidates[peerUserId] ?? const <RTCIceCandidate>[];
    if (queue.isEmpty) return;
    for (final candidate in queue) {
      await pc.addCandidate(candidate);
    }
    _pendingCandidates[peerUserId] = <RTCIceCandidate>[];
  }

  Future<void> _sendSignal({
    required String type,
    required String toUserId,
    required String toClientId,
    required Map<String, dynamic> data,
  }) async {
    final uid = _selfUid;
    if (uid == null || uid.isEmpty) return;
    final user = _auth.currentUser;
    try {
      await _signaling.send({
        'type': type,
        'sessionKey': _sessionKey,
        'conversationId': widget.conversationId,
        'channelId': widget.channelId,
        'from': uid,
        'fromClientId': _signaling.clientId,
        'fromDisplayName': user?.displayName ?? 'User',
        'fromPhotoUrl': user?.photoURL ?? '',
        'to': toUserId,
        'toClientId': toClientId,
        ...data,
      });
    } catch (e) {
      debugPrint('Voice signaling send failed: $e');
    }
  }

  Future<void> _toggleMute() async {
    _isMuted = !_isMuted;
    final local = _localStream;
    if (local != null) {
      for (final track in local.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
    await _updatePresenceHeartbeat();
    if (mounted) setState(() {});
  }

  Future<void> _toggleDeafen() async {
    _isDeafened = !_isDeafened;
    for (final stream in _remoteStreams.values) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_isDeafened;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    if (Platform.isAndroid || Platform.isIOS) {
      await Helper.setSpeakerphoneOn(_speakerOn);
    }
    if (mounted) setState(() {});
  }

  Future<void> _closePeerConnection(String peerUserId) async {
    final pc = _peerConnections.remove(peerUserId);
    final stream = _remoteStreams.remove(peerUserId);
    _pendingCandidates.remove(peerUserId);
    _remoteDescriptionSet.remove(peerUserId);
    _peerClientIds.remove(peerUserId);
    try {
      await pc?.close();
    } catch (_) {}
    try {
      await stream?.dispose();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _leaveVoiceChannel({bool closeScreen = false}) async {
    if (_isLeaving) return;
    _isLeaving = true;

    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = null;
    await _signalSub?.cancel();
    await _presenceSub?.cancel();
    _signalSub = null;
    _presenceSub = null;

    final peers = _peerClientIds.entries.toList();
    for (final peer in peers) {
      final uid = _selfUid;
      if (uid != null && uid.isNotEmpty) {
        try {
          await _signaling.send({
            'type': 'voice_leave',
            'sessionKey': _sessionKey,
            'conversationId': widget.conversationId,
            'channelId': widget.channelId,
            'from': uid,
            'fromClientId': _signaling.clientId,
            'to': peer.key,
            'toClientId': peer.value,
          });
        } catch (_) {}
      }
      await _closePeerConnection(peer.key);
    }

    final local = _localStream;
    if (local != null) {
      for (final track in local.getTracks()) {
        track.stop();
      }
      await local.dispose();
      _localStream = null;
    }

    final uid = _selfUid;
    if (_joinedPresence && uid != null && uid.isNotEmpty) {
      try {
        await _voiceDocRef.set({
          'activeMembers.$uid': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    _joinedPresence = false;
    ActiveSessionService().clearSession(sessionId: _sessionId);
    if (closeScreen && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _minimizeToHome() async {
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(suppressInviteHandling: true),
      ),
    );
  }

  String? _normalizePhotoUrl(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return text;
  }

  String _connectionLabel(String userId) {
    final pc = _peerConnections[userId];
    if (pc == null) return 'Waiting';
    switch (pc.connectionState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Connected';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return 'Connecting';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Failed';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Disconnected';
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return 'Closed';
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      default:
        return 'Waiting';
    }
  }

  List<_VoiceMember> _sortedMembers() {
    final self = _selfUid;
    final list = _members.values.toList();
    list.sort((a, b) {
      final aSelf = self != null && a.userId == self;
      final bSelf = self != null && b.userId == self;
      if (aSelf && !bSelf) return -1;
      if (bSelf && !aSelf) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  Widget _buildParticipantTile(_VoiceMember member) {
    final self = _selfUid;
    final isSelf = self != null && member.userId == self;
    final avatarUrl = _normalizePhotoUrl(member.photoUrl);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[300],
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Icon(Icons.person, color: Colors.grey[700], size: 18)
              : null,
        ),
        title: Text(
          isSelf ? '${member.displayName} (You)' : member.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isSelf ? 'Connected' : _connectionLabel(member.userId),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 6,
          children: [
            if (member.muted)
              const Icon(Icons.mic_off, size: 18, color: Colors.redAccent),
            if (isSelf && _isDeafened)
              const Icon(
                Icons.hearing_disabled,
                size: 18,
                color: Colors.orange,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
    Color? activeColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = active
        ? (activeColor ?? colorScheme.primary)
        : colorScheme.surfaceContainerHigh;
    final fgColor = active ? colorScheme.onPrimary : colorScheme.onSurface;

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _sendVoiceTextMessage() async {
    final user = _auth.currentUser;
    if (user == null || _isSendingVoiceText) return;
    final text = _voiceChatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSendingVoiceText = true;
    });
    _voiceChatController.clear();

    try {
      await _voiceMessagesRef.add({
        'senderId': user.uid,
        'senderName': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'User',
        'senderPhotoUrl': user.photoURL ?? '',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': Timestamp.now(),
      });
    } catch (e) {
      if (!mounted) return;
      _voiceChatController.text = text;
      _voiceChatController.selection = TextSelection.fromPosition(
        TextPosition(offset: _voiceChatController.text.length),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send voice chat message: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingVoiceText = false;
        });
      }
    }
  }

  Widget _buildMembersPanel() {
    if (_members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.group,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for participants...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      children: _sortedMembers().map(_buildParticipantTile).toList(),
    );
  }

  Widget _buildVoiceTextPanel() {
    final themeService = context.watch<ThemeService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _voiceMessagesRef
                .orderBy('clientTimestamp', descending: true)
                .limit(150)
                .safeSnapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load channel chat',
                    style: TextStyle(color: colorScheme.error),
                  ),
                );
              }
              final docs = snapshot.data?.docs ?? const [];
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'Voice channel chat is empty',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                );
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final message = _VoiceChannelTextMessage.fromMap(data);
                  return _buildVoiceTextMessageTile(
                    message: message,
                    showPreviews: themeService.showLinkPreviews,
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _voiceChatController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => unawaited(_sendVoiceTextMessage()),
                  decoration: InputDecoration(
                    hintText: 'Message this voice channel',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSendingVoiceText
                    ? null
                    : () => unawaited(_sendVoiceTextMessage()),
                icon: _isSendingVoiceText
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceTextMessageTile({
    required _VoiceChannelTextMessage message,
    required bool showPreviews,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMe = message.senderId == _selfUid;
    final textColor = isMe ? colorScheme.onPrimary : colorScheme.onSurface;
    final bubbleColor = isMe
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;

    final time = message.timestamp == null
        ? ''
        : TimeOfDay.fromDateTime(message.timestamp!).format(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    message.senderName,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ChatMessageText(
                text: message.text,
                style: TextStyle(color: textColor, fontSize: 14),
                linkStyle: TextStyle(
                  color: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.95)
                      : colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
                showPreviews: showPreviews,
                maxPreviewCards: 1,
                previewBackgroundColor: isMe
                    ? colorScheme.onPrimary.withValues(alpha: 0.14)
                    : colorScheme.surfaceContainerHigh,
                previewBorderColor: isMe
                    ? colorScheme.onPrimary.withValues(alpha: 0.24)
                    : colorScheme.outlineVariant.withValues(alpha: 0.44),
                previewTitleColor: textColor,
                previewMetaColor: textColor.withValues(alpha: 0.76),
              ),
              if (time.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    time,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.72),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_leaveVoiceChannel());
    ActiveSessionService().clearSession(sessionId: _sessionId);
    _voiceChatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.conversationTitle} | Voice',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '#${widget.channelName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _minimizeToHome,
            tooltip: 'Open chats',
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Text(
                    '${_members.length} participant${_members.length == 1 ? '' : 's'} in voice channel',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: TabBar(
                            tabs: const [
                              Tab(text: 'People', icon: Icon(Icons.groups)),
                              Tab(text: 'Chat', icon: Icon(Icons.chat_bubble)),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildMembersPanel(),
                              _buildVoiceTextPanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildControlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          label: _isMuted ? 'Unmute' : 'Mute',
                          active: _isMuted,
                          activeColor: Colors.red,
                          onPressed: () => unawaited(_toggleMute()),
                        ),
                        _buildControlButton(
                          icon: _isDeafened
                              ? Icons.hearing_disabled
                              : Icons.hearing,
                          label: _isDeafened ? 'Undeafen' : 'Deafen',
                          active: _isDeafened,
                          activeColor: Colors.orange,
                          onPressed: () => unawaited(_toggleDeafen()),
                        ),
                        if (Platform.isAndroid || Platform.isIOS)
                          _buildControlButton(
                            icon: _speakerOn
                                ? Icons.volume_up
                                : Icons.volume_down,
                            label: _speakerOn ? 'Speaker' : 'Earpiece',
                            active: _speakerOn,
                            onPressed: () => unawaited(_toggleSpeaker()),
                          ),
                        _buildControlButton(
                          icon: Icons.call_end,
                          label: 'Leave',
                          active: true,
                          activeColor: Colors.red,
                          onPressed: () =>
                              unawaited(_leaveVoiceChannel(closeScreen: true)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _VoiceMember {
  final String userId;
  final String clientId;
  final String displayName;
  final String photoUrl;
  final bool muted;
  final Timestamp? joinedAt;
  final Timestamp? updatedAt;

  const _VoiceMember({
    required this.userId,
    required this.clientId,
    required this.displayName,
    required this.photoUrl,
    required this.muted,
    required this.joinedAt,
    required this.updatedAt,
  });

  factory _VoiceMember.fromMap({
    required String userId,
    required Map<String, dynamic> data,
  }) {
    return _VoiceMember(
      userId: userId,
      clientId: data['clientId']?.toString().trim() ?? '',
      displayName: data['displayName']?.toString().trim().isNotEmpty == true
          ? data['displayName'].toString().trim()
          : 'Member',
      photoUrl: data['photoUrl']?.toString().trim() ?? '',
      muted: data['muted'] == true,
      joinedAt: data['joinedAt'] is Timestamp
          ? data['joinedAt'] as Timestamp
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null,
    );
  }
}

class _VoiceChannelTextMessage {
  final String senderId;
  final String senderName;
  final String senderPhotoUrl;
  final String text;
  final DateTime? timestamp;

  const _VoiceChannelTextMessage({
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.text,
    required this.timestamp,
  });

  factory _VoiceChannelTextMessage.fromMap(Map<String, dynamic> data) {
    final timestamp = data['timestamp'] is Timestamp
        ? (data['timestamp'] as Timestamp).toDate()
        : (data['clientTimestamp'] is Timestamp
              ? (data['clientTimestamp'] as Timestamp).toDate()
              : null);
    final senderNameRaw = data['senderName']?.toString().trim() ?? '';
    return _VoiceChannelTextMessage(
      senderId: data['senderId']?.toString().trim() ?? '',
      senderName: senderNameRaw.isEmpty ? 'Member' : senderNameRaw,
      senderPhotoUrl: data['senderPhotoUrl']?.toString().trim() ?? '',
      text: data['text']?.toString() ?? '',
      timestamp: timestamp,
    );
  }
}
