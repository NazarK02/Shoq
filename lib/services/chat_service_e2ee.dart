import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'crypto_service.dart';
import 'device_info_service.dart';

class ChatFileUpload {
  final String messageId;
  final String storagePath;
  final UploadTask task;
  final String contentType;

  ChatFileUpload({
    required this.messageId,
    required this.storagePath,
    required this.task,
    required this.contentType,
  });
}

/// Chat service with end-to-end encryption
///
/// All messages are encrypted before being sent to Firestore.
/// Automatically initializes E2EE for both users when needed.
class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final CryptoService _crypto = CryptoService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();

  User? get currentUser => _auth.currentUser;
  bool get isEncryptionReady => _crypto.isEncryptionEnabled;

  Future<Map<String, dynamic>> _fetchUserData(String userId) async {
    try {
      final serverDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      final data = serverDoc.data();
      if (data != null) return data;
    } catch (_) {}

    try {
      final cacheDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.cache));
      return cacheDoc.data() ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Initialize encryption before using chat
  Future<void> initializeEncryption() async {
    await _crypto.initialize();
  }

  /// Generate conversation ID for direct messages
  String getDirectConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'direct_${sortedIds.join('_')}';
  }

  /// Initialize or get existing conversation
  /// Also ensures both users have E2EE enabled
  Future<String?> initializeConversation(String recipientId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;

    // Ensure current user has E2EE
    await _ensureUserHasE2EE(currentUser.uid);

    // Ensure recipient has E2EE
    await _ensureUserHasE2EE(recipientId);

    final conversationId = getDirectConversationId(
      currentUser.uid,
      recipientId,
    );

    final conversationDoc = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .get();

    if (!conversationDoc.exists) {
      await _firestore.collection('conversations').doc(conversationId).set({
        'type': 'direct',
        'participants': [currentUser.uid, recipientId],
        'createdBy': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': null,
        'encrypted': true,
        'hasMessages': false, // Track if conversation has any messages
      });
    }

    return conversationId;
  }

  Map<String, String> _extractDevicePublicKeys(dynamic devicesRaw) {
    final keys = <String, String>{};
    void addKey(String deviceId, String publicKey) {
      final sanitized = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final baseId = sanitized.trim().isEmpty ? 'device' : sanitized.trim();
      var uniqueId = baseId;
      var index = 1;
      while (keys.containsKey(uniqueId)) {
        index++;
        uniqueId = '${baseId}_$index';
      }
      keys[uniqueId] = publicKey;
    }

    void walk(dynamic node, String path) {
      if (node is! Map) return;

      final map = <String, dynamic>{};
      for (final entry in node.entries) {
        map[entry.key.toString()] = entry.value;
      }

      final publicKey = map['publicKey'];
      if (publicKey is String && publicKey.isNotEmpty) {
        addKey(path, publicKey);
      }

      for (final entry in map.entries) {
        if (entry.key == 'publicKey') continue;
        final nextPath = path.isEmpty ? entry.key : '$path.${entry.key}';
        walk(entry.value, nextPath);
      }
    }

    walk(devicesRaw, '');
    return keys;
  }

  /// Ensure a user has E2EE keys (initialize if needed)
  Future<_UserKeySet> _ensureUserHasE2EE(String userId) async {
    final data = await _fetchUserData(userId);

    String? legacyKey = data['publicKey'] as String?;
    final deviceKeys = _extractDevicePublicKeys(data['devices']);

    if (userId == _auth.currentUser?.uid) {
      await _crypto.initialize();
      final publicKey = _crypto.myPublicKeyBase64;

      if (publicKey != null) {
        final device = await _deviceInfo.getDeviceInfo();
        final deviceId = device['deviceId'] ?? 'unknown';

        final updates = <String, dynamic>{};

        if (deviceKeys[deviceId] != publicKey) {
          updates['devices.$deviceId.publicKey'] = publicKey;
          updates['devices.$deviceId.publicKeyUpdatedAt'] =
              FieldValue.serverTimestamp();
          deviceKeys[deviceId] = publicKey;
        }

        if (legacyKey == null || legacyKey.isEmpty) {
          updates['publicKey'] = publicKey;
          updates['publicKeyUpdatedAt'] = FieldValue.serverTimestamp();
          legacyKey = publicKey;
        }

        if (updates.isNotEmpty) {
          await _firestore
              .collection('users')
              .doc(userId)
              .set(updates, SetOptions(merge: true));
        }
      }
    } else if (legacyKey == null && deviceKeys.isEmpty) {
      print('Cannot initialize E2EE for other user; they must login first');
    }

    return _UserKeySet(legacyKey: legacyKey, deviceKeys: deviceKeys);
  }

  Future<Map<String, dynamic>> _buildEncryptedTextPayloadForRecipients({
    required String messageText,
    required List<String> recipientIds,
    bool includeTimestamps = true,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    if (!_crypto.isEncryptionEnabled) {
      throw Exception(
        'Encryption not initialized. Call initializeEncryption() first.',
      );
    }

    final uniqueRecipientIds = recipientIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != currentUser.uid)
        .toSet()
        .toList();
    if (uniqueRecipientIds.isEmpty) {
      throw Exception('No recipients provided for encrypted message');
    }

    final senderKeys = await _ensureUserHasE2EE(currentUser.uid);

    final device = await _deviceInfo.getDeviceInfo();
    final senderDeviceId = device['deviceId'] ?? 'unknown';
    final senderDeviceKeys = Map<String, String>.from(senderKeys.deviceKeys);
    final myPublicKey = _crypto.myPublicKeyBase64;
    if (myPublicKey != null && !senderDeviceKeys.containsKey(senderDeviceId)) {
      senderDeviceKeys[senderDeviceId] = myPublicKey;
    }

    final recipientCiphertexts = <String, String>{};
    final recipientCiphertextsByKey = <String, String>{};
    final recipientCipherCache = <String, String>{};
    String? legacyRecipientCiphertext;
    for (final recipientId in uniqueRecipientIds) {
      final recipientKeys = await _ensureUserHasE2EE(recipientId);
      if (!recipientKeys.hasAnyKey) {
        continue;
      }

      for (final entry in recipientKeys.deviceKeys.entries) {
        final publicKey = entry.value.trim();
        if (publicKey.isEmpty) continue;

        final keyId = _publicKeyId(publicKey);
        final ciphertext =
            recipientCipherCache[keyId] ??
            await _crypto.encryptMessageWithPublicKey(
              plaintext: messageText,
              recipientPublicKeyBase64: publicKey,
            );

        recipientCipherCache[keyId] = ciphertext;
        recipientCiphertexts['$recipientId::${entry.key}'] = ciphertext;
        recipientCiphertextsByKey[keyId] = ciphertext;
        legacyRecipientCiphertext ??= ciphertext;
      }

      if (recipientKeys.legacyKey != null &&
          recipientKeys.legacyKey!.trim().isNotEmpty) {
        final legacyPublicKey = recipientKeys.legacyKey!.trim();
        final legacyKeyId = _publicKeyId(legacyPublicKey);
        final legacyCiphertext =
            recipientCipherCache[legacyKeyId] ??
            await _crypto.encryptMessageWithPublicKey(
              plaintext: messageText,
              recipientPublicKeyBase64: legacyPublicKey,
            );
        recipientCipherCache[legacyKeyId] = legacyCiphertext;
        recipientCiphertextsByKey[legacyKeyId] = legacyCiphertext;
        legacyRecipientCiphertext ??= legacyCiphertext;
      }
    }

    if (recipientCiphertextsByKey.isEmpty &&
        legacyRecipientCiphertext == null) {
      throw Exception('Recipients have no encryption keys');
    }

    final senderCiphertexts = <String, String>{};
    final senderCiphertextsByKey = <String, String>{};
    final senderCipherCache = <String, String>{};
    for (final entry in senderDeviceKeys.entries) {
      final publicKey = entry.value.trim();
      if (publicKey.isEmpty) continue;

      final keyId = _publicKeyId(publicKey);
      final ciphertext =
          senderCipherCache[keyId] ??
          await _crypto.encryptMessageWithPublicKey(
            plaintext: messageText,
            recipientPublicKeyBase64: publicKey,
          );

      senderCipherCache[keyId] = ciphertext;
      senderCiphertexts[entry.key] = ciphertext;
      senderCiphertextsByKey[keyId] = ciphertext;
    }

    String? legacySenderCiphertext;
    if (senderKeys.legacyKey != null && senderKeys.legacyKey!.isNotEmpty) {
      final legacyPublicKey = senderKeys.legacyKey!.trim();
      final legacyKeyId = _publicKeyId(legacyPublicKey);
      legacySenderCiphertext =
          senderCipherCache[legacyKeyId] ??
          await _crypto.encryptMessageWithPublicKey(
            plaintext: messageText,
            recipientPublicKeyBase64: legacyPublicKey,
          );
      senderCiphertextsByKey[legacyKeyId] = legacySenderCiphertext;
    }

    final payload = <String, dynamic>{
      'senderId': currentUser.uid,
      'senderDeviceId': senderDeviceId,
      'read': false,
      'encrypted': true,
      'type': 'text',
      'encryptionVersion': 3,
    };
    if (includeTimestamps) {
      payload['timestamp'] = FieldValue.serverTimestamp();
      payload['clientTimestamp'] = Timestamp.now();
    }

    if (myPublicKey != null && myPublicKey.isNotEmpty) {
      payload['senderPublicKey'] = myPublicKey;
      payload['senderKeyId'] = _publicKeyId(myPublicKey);
    }
    payload['recipientIds'] = uniqueRecipientIds;
    if (recipientCiphertexts.isNotEmpty) {
      payload['ciphertexts'] = recipientCiphertexts;
    }
    if (recipientCiphertextsByKey.isNotEmpty) {
      payload['ciphertextsByKey'] = recipientCiphertextsByKey;
    }
    if (senderCiphertexts.isNotEmpty) {
      payload['senderCiphertexts'] = senderCiphertexts;
    }
    if (senderCiphertextsByKey.isNotEmpty) {
      payload['senderCiphertextsByKey'] = senderCiphertextsByKey;
    }
    if (legacyRecipientCiphertext != null) {
      payload['ciphertext'] = legacyRecipientCiphertext;
    }
    if (legacySenderCiphertext != null) {
      payload['senderCiphertext'] = legacySenderCiphertext;
    }

    return payload;
  }

  Future<Map<String, dynamic>> _buildEncryptedTextPayload({
    required String messageText,
    required String recipientId,
    bool includeTimestamps = true,
  }) {
    return _buildEncryptedTextPayloadForRecipients(
      messageText: messageText,
      recipientIds: [recipientId],
      includeTimestamps: includeTimestamps,
    );
  }

  String _buildMessagePreview(String messageText) {
    final normalized = messageText.trim();
    if (normalized.isEmpty) return '';
    return normalized.length > 50
        ? '${normalized.substring(0, 50)}...'
        : normalized;
  }

  /// Send an encrypted message
  Future<void> sendMessage({
    required String conversationId,
    required String messageText,
    required String recipientId,
    String? messageId,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
    Map<String, dynamic>? callSummary,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');
    if (messageText.trim().isEmpty) return;

    print('Sending encrypted message...');

    try {
      // Get first 50 chars of plaintext for preview in chat list.
      final preview = _buildMessagePreview(messageText);

      final payload = await _buildEncryptedTextPayload(
        messageText: messageText,
        recipientId: recipientId,
      );

      final trimmedReplyId = replyToMessageId?.trim();
      final trimmedReplyText = replyToText?.trim();
      final trimmedReplySenderId = replyToSenderId?.trim();
      if (trimmedReplyId != null && trimmedReplyId.isNotEmpty) {
        payload['replyToMessageId'] = trimmedReplyId;
      }
      if (trimmedReplyText != null && trimmedReplyText.isNotEmpty) {
        payload['replyToText'] = trimmedReplyText.length > 120
            ? '${trimmedReplyText.substring(0, 120)}...'
            : trimmedReplyText;
      }
      if (trimmedReplySenderId != null && trimmedReplySenderId.isNotEmpty) {
        payload['replyToSenderId'] = trimmedReplySenderId;
      }
      if (callSummary != null && callSummary.isNotEmpty) {
        payload['callSummary'] = Map<String, dynamic>.from(callSummary);
      }

      // Store encrypted message. Allow caller-provided IDs for optimistic UI
      // and idempotent writes (for example call summaries).
      final messagesRef = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages');
      final trimmedMessageId = messageId?.trim();
      final messageRef =
          (trimmedMessageId != null && trimmedMessageId.isNotEmpty)
          ? messagesRef.doc(trimmedMessageId)
          : messagesRef.doc();
      await messageRef.set(payload);

      // Update conversation metadata with plaintext preview for UI
      await _firestore.collection('conversations').doc(conversationId).update({
        'lastMessage': preview,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
        'hasMessages': true,
      });

      print('Encrypted message sent successfully');
    } catch (e) {
      print('Failed to send encrypted message: $e');
      rethrow;
    }
  }

  Future<void> sendRoomMessage({
    required String conversationId,
    required String messageText,
    required List<String> participantIds,
    String? messageId,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
    Map<String, dynamic>? callSummary,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    final trimmedText = messageText.trim();
    if (trimmedText.isEmpty) return;

    final recipientIds = participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != currentUser.uid)
        .toSet()
        .toList();
    if (recipientIds.isEmpty) {
      throw Exception('Conversation has no recipients');
    }

    final payload = await _buildEncryptedTextPayloadForRecipients(
      messageText: trimmedText,
      recipientIds: recipientIds,
    );

    final trimmedReplyId = replyToMessageId?.trim();
    final trimmedReplyText = replyToText?.trim();
    final trimmedReplySenderId = replyToSenderId?.trim();
    if (trimmedReplyId != null && trimmedReplyId.isNotEmpty) {
      payload['replyToMessageId'] = trimmedReplyId;
    }
    if (trimmedReplyText != null && trimmedReplyText.isNotEmpty) {
      payload['replyToText'] = trimmedReplyText.length > 120
          ? '${trimmedReplyText.substring(0, 120)}...'
          : trimmedReplyText;
    }
    if (trimmedReplySenderId != null && trimmedReplySenderId.isNotEmpty) {
      payload['replyToSenderId'] = trimmedReplySenderId;
    }
    if (callSummary != null && callSummary.isNotEmpty) {
      payload['callSummary'] = Map<String, dynamic>.from(callSummary);
    }

    final messagesRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');
    final trimmedMessageId = messageId?.trim();
    final messageRef = (trimmedMessageId != null && trimmedMessageId.isNotEmpty)
        ? messagesRef.doc(trimmedMessageId)
        : messagesRef.doc();
    await messageRef.set(payload);

    await _firestore.collection('conversations').doc(conversationId).set({
      'lastMessage': _buildMessagePreview(trimmedText),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUser.uid,
      'hasMessages': true,
    }, SetOptions(merge: true));
  }

  /// Edit an existing encrypted text message.
  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String recipientId,
    required String messageText,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    final trimmed = messageText.trim();
    if (trimmed.isEmpty) return;

    final payload = await _buildEncryptedTextPayload(
      messageText: trimmed,
      recipientId: recipientId,
      includeTimestamps: false,
    );
    payload['edited'] = true;
    payload['editedAt'] = FieldValue.serverTimestamp();
    payload['read'] = false;
    payload['readAt'] = FieldValue.delete();

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update(payload);

    final preview = trimmed.length > 50
        ? '${trimmed.substring(0, 50)}...'
        : trimmed;
    await _firestore.collection('conversations').doc(conversationId).set({
      'lastMessage': preview,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUser.uid,
      'hasMessages': true,
    }, SetOptions(merge: true));
  }

  /// Send a file message (non-encrypted file contents).

  Future<void> sendFileMessage({
    required String conversationId,
    required String recipientId,
    required String filePath,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final upload = startFileUpload(
      conversationId: conversationId,
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
    );

    await upload.task;

    await commitFileMessage(
      conversationId: conversationId,
      messageId: upload.messageId,
      storagePath: upload.storagePath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: upload.contentType,
    );
  }

  ChatFileUpload startFileUpload({
    required String conversationId,
    required String filePath,
    required String fileName,
    String? mimeType,
  }) {
    if (filePath.trim().isEmpty) {
      throw Exception('Invalid file path');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File not found');
    }

    final displayName = fileName.trim().isEmpty ? 'file' : fileName.trim();
    final safeName = displayName.replaceAll(RegExp(r'[\\\\/]+'), '_');
    final messageId = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc()
        .id;
    final storagePath = 'chat_files/$conversationId/${messageId}_$safeName';
    final ref = _storage.ref().child(storagePath);

    final contentType = (mimeType == null || mimeType.trim().isEmpty)
        ? 'application/octet-stream'
        : mimeType.trim();

    final task = ref.putFile(file, SettableMetadata(contentType: contentType));

    return ChatFileUpload(
      messageId: messageId,
      storagePath: storagePath,
      task: task,
      contentType: contentType,
    );
  }

  Future<void> commitFileMessage({
    required String conversationId,
    required String messageId,
    required String storagePath,
    String? downloadUrl,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    final displayName = fileName.trim().isEmpty ? 'file' : fileName.trim();
    final contentType = (mimeType == null || mimeType.trim().isEmpty)
        ? 'application/octet-stream'
        : mimeType.trim();

    final payload = <String, dynamic>{
      'senderId': currentUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'clientTimestamp': Timestamp.now(),
      'read': false,
      'encrypted': false,
      'type': 'file',
      'fileName': displayName,
      'fileSize': fileSize,
      'mimeType': contentType,
      'storagePath': storagePath,
    };

    if (downloadUrl != null && downloadUrl.trim().isNotEmpty) {
      payload['fileUrl'] = downloadUrl.trim();
    }

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .set(payload);

    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': 'File: $displayName',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUser.uid,
      'hasMessages': true,
    });
  }

  /// Get messages stream (returns encrypted messages)
  Stream<QuerySnapshot> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        // clientTimestamp is available immediately and avoids reorder jitter
        // while server timestamps are being resolved.
        .orderBy('clientTimestamp', descending: false)
        .snapshots();
  }

  /// Reads recent messages from Firestore local cache for instant first paint.
  Future<QuerySnapshot?> getCachedMessages(
    String conversationId, {
    int limit = 120,
  }) async {
    try {
      return await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('clientTimestamp', descending: false)
          .limitToLast(limit)
          .get(const GetOptions(source: Source.cache));
    } catch (_) {
      return null;
    }
  }

  void _addUniqueString(List<String> target, String? value) {
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (!target.contains(trimmed)) {
      target.add(trimmed);
    }
  }

  String _publicKeyId(String publicKeyBase64) {
    final digest = sha256.convert(utf8.encode(publicKeyBase64.trim()));
    return 'key_${digest.toString().substring(0, 24)}';
  }

  List<String> _collectCiphertextCandidates({
    required Map<String, dynamic> messageData,
    required bool isOwnMessage,
    required String currentDeviceId,
    String? currentPublicKeyId,
  }) {
    final candidates = <String>[];

    void collectFromMap(dynamic raw, {String? preferredKey}) {
      if (raw is! Map) return;

      if (preferredKey != null && preferredKey.isNotEmpty) {
        final preferred = raw[preferredKey];
        if (preferred is String) {
          _addUniqueString(candidates, preferred);
        }
      }

      for (final value in raw.values) {
        if (value is String) {
          _addUniqueString(candidates, value);
        }
      }
    }

    if (isOwnMessage) {
      collectFromMap(
        messageData['senderCiphertextsByKey'],
        preferredKey: currentPublicKeyId,
      );
      collectFromMap(
        messageData['senderCiphertexts'],
        preferredKey: currentDeviceId,
      );

      final legacySenderCipher = messageData['senderCiphertext'];
      if (legacySenderCipher is String) {
        _addUniqueString(candidates, legacySenderCipher);
      }
      return candidates;
    }

    collectFromMap(
      messageData['ciphertextsByKey'],
      preferredKey: currentPublicKeyId,
    );
    collectFromMap(messageData['ciphertexts'], preferredKey: currentDeviceId);

    final legacyCipher = messageData['ciphertext'];
    if (legacyCipher is String) {
      _addUniqueString(candidates, legacyCipher);
    }
    return candidates;
  }

  Future<List<String>> _resolveSenderPublicKeys({
    required String senderId,
    String? senderDeviceId,
    String? messageSenderPublicKey,
    String? localSenderPublicKey,
  }) async {
    final publicKeys = <String>[];

    _addUniqueString(publicKeys, messageSenderPublicKey);
    _addUniqueString(publicKeys, localSenderPublicKey);

    final data = await _fetchUserData(senderId);
    if (data.isEmpty) {
      return publicKeys;
    }

    final devices = data['devices'];

    if (senderDeviceId != null && senderDeviceId.isNotEmpty && devices is Map) {
      final deviceEntry = devices[senderDeviceId];
      if (deviceEntry is Map && deviceEntry['publicKey'] is String) {
        _addUniqueString(publicKeys, deviceEntry['publicKey'] as String?);
      }
    }

    _addUniqueString(publicKeys, data['publicKey'] as String?);

    void walk(dynamic node) {
      if (node is! Map) return;
      for (final value in node.values) {
        if (value is Map && value['publicKey'] is String) {
          _addUniqueString(publicKeys, value['publicKey'] as String?);
        }
        walk(value);
      }
    }

    walk(devices);
    return publicKeys;
  }

  Future<void> backfillSenderPublicKeyForConversation(
    String conversationId,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (!_crypto.isEncryptionEnabled) {
      await _crypto.initialize();
    }

    final myPublicKey = _crypto.myPublicKeyBase64;
    if (myPublicKey == null || myPublicKey.isEmpty) return;
    final mySenderKeyId = _publicKeyId(myPublicKey);

    final device = await _deviceInfo.getDeviceInfo();
    final currentDeviceId = device['deviceId'] ?? 'unknown';

    final query = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(300)
        .get();

    final batch = _firestore.batch();
    var updates = 0;

    for (final doc in query.docs) {
      final data = doc.data();
      final encrypted = data['encrypted'] == true;
      final senderId = data['senderId']?.toString();
      final senderDeviceId = data['senderDeviceId']?.toString();
      final senderPublicKey = data['senderPublicKey']?.toString();
      final senderKeyId = data['senderKeyId']?.toString();

      if (!encrypted) continue;
      if (senderId != currentUser.uid) continue;
      if (senderDeviceId != currentDeviceId) continue;

      final docUpdates = <String, dynamic>{};
      if (senderPublicKey == null || senderPublicKey.trim().isEmpty) {
        docUpdates['senderPublicKey'] = myPublicKey;
      }
      if (senderKeyId == null || senderKeyId.trim().isEmpty) {
        docUpdates['senderKeyId'] = mySenderKeyId;
      }

      if (docUpdates.isNotEmpty) {
        batch.update(doc.reference, docUpdates);
        updates++;
      }
    }

    if (updates > 0) {
      await batch.commit();
    }
  }

  /// Decrypt a single message
  Future<String> decryptMessage({
    required Map<String, dynamic> messageData,
  }) async {
    if (!_crypto.isEncryptionEnabled) {
      return '';
    }

    try {
      // Check if message is encrypted
      if (messageData['encrypted'] != true) {
        return (messageData['text'] ?? messageData['message'] ?? '').toString();
      }

      final senderId = messageData['senderId'] as String?;
      if (senderId == null) {
        return '';
      }

      final senderDeviceId = messageData['senderDeviceId'] as String?;
      final device = await _deviceInfo.getDeviceInfo();
      final currentDeviceId = device['deviceId'] ?? 'unknown';
      final currentPublicKey = _crypto.myPublicKeyBase64;
      final currentPublicKeyId =
          (currentPublicKey != null && currentPublicKey.isNotEmpty)
          ? _publicKeyId(currentPublicKey)
          : null;

      final currentUserId = _auth.currentUser?.uid;
      final isOwnMessage = currentUserId != null && senderId == currentUserId;
      final ciphertextCandidates = _collectCiphertextCandidates(
        messageData: messageData,
        isOwnMessage: isOwnMessage,
        currentDeviceId: currentDeviceId,
        currentPublicKeyId: currentPublicKeyId,
      );

      if (ciphertextCandidates.isEmpty) {
        return '';
      }

      final senderPublicKeys = await _resolveSenderPublicKeys(
        senderId: senderId,
        senderDeviceId: senderDeviceId,
        messageSenderPublicKey: messageData['senderPublicKey'] is String
            ? messageData['senderPublicKey'] as String
            : null,
        localSenderPublicKey: isOwnMessage ? currentPublicKey : null,
      );
      if (senderPublicKeys.isEmpty) {
        return '';
      }

      for (final ciphertext in ciphertextCandidates) {
        for (final senderPublicKey in senderPublicKeys) {
          try {
            final plaintext = await _crypto.decryptMessageWithSenderPublicKey(
              ciphertextBase64: ciphertext,
              senderPublicKeyBase64: senderPublicKey,
            );
            if (plaintext.isNotEmpty) {
              return plaintext;
            }
          } catch (_) {
            // Try other key/ciphertext combinations.
          }
        }
      }

      return '';
    } catch (e) {
      print('Decryption failed: $e');
      return '';
    }
  }

  /// Get conversation stream

  Stream<DocumentSnapshot> getConversation(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .snapshots();
  }

  /// Clear all messages in a conversation
  Future<void> clearChat(String conversationId) async {
    final messages = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': null,
      'lastMessageTime': null,
      'hasMessages': false,
    });
  }

  /// Delete a specific message
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String otherUserId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      final unreadMessages = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isEqualTo: otherUserId)
          .where('read', isEqualTo: false)
          .get();

      if (unreadMessages.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        print('markMessagesAsRead permission denied for $conversationId');
        return;
      }
      rethrow;
    }
  }

  /// Get user conversations
  Stream<QuerySnapshot> getUserConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots();
  }

  /// Get user data
  Future<DocumentSnapshot> getUserData(String userId) {
    return _firestore.collection('users').doc(userId).get();
  }

  /// Check if user has encryption enabled
  Future<bool> userHasEncryption(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data();
    if (data == null) return false;
    if (data['publicKey'] != null) return true;
    final deviceKeys = _extractDevicePublicKeys(data['devices']);
    return deviceKeys.isNotEmpty;
  }
}

class _UserKeySet {
  final String? legacyKey;
  final Map<String, String> deviceKeys;

  const _UserKeySet({required this.legacyKey, required this.deviceKeys});

  bool get hasAnyKey =>
      (legacyKey != null && legacyKey!.isNotEmpty) || deviceKeys.isNotEmpty;
}
