import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  Map<String, String>? _cached;
  String? _installIdCache;

  static const String _installIdKey = 'device_install_id_v1';

  String _stableDeviceId({required String deviceType, required String rawId}) {
    final normalizedRaw = rawId.trim().isEmpty ? deviceType : rawId.trim();
    final digest = sha256.convert(utf8.encode('$deviceType|$normalizedRaw'));
    return 'dev_${digest.toString().substring(0, 24)}';
  }

  bool _isWeakRawId(String rawId, String deviceType) {
    final normalized = rawId.trim().toLowerCase();
    if (normalized.isEmpty) return true;

    const weakTokens = <String>{
      'unknown',
      'undefined',
      'null',
      'n/a',
      'na',
      'web',
      'android',
      'ios',
      'windows',
      'macos',
    };

    if (weakTokens.contains(normalized)) return true;
    if (normalized == deviceType.toLowerCase()) return true;

    return false;
  }

  String _generateInstallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> _getOrCreateInstallId() async {
    if (_installIdCache != null && _installIdCache!.isNotEmpty) {
      return _installIdCache!;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      _installIdCache = existing.trim();
      return _installIdCache!;
    }

    final created = _generateInstallId();
    await prefs.setString(_installIdKey, created);
    _installIdCache = created;
    return created;
  }

  Future<Map<String, String>> getDeviceInfo() async {
    if (_cached != null) return _cached!;

    String rawId = 'unknown';
    String deviceType = 'unknown';

    if (kIsWeb) {
      rawId = 'web';
      deviceType = 'web';
    } else if (Platform.isAndroid) {
      final android = await _deviceInfo.androidInfo;
      rawId = android.id;
      deviceType = 'android';
    } else if (Platform.isIOS) {
      final ios = await _deviceInfo.iosInfo;
      rawId = ios.identifierForVendor ?? 'ios';
      deviceType = 'ios';
    } else if (Platform.isWindows) {
      final windows = await _deviceInfo.windowsInfo;
      rawId = windows.deviceId;
      deviceType = 'windows';
    } else if (Platform.isMacOS) {
      final mac = await _deviceInfo.macOsInfo;
      rawId = mac.systemGUID ?? 'macos';
      deviceType = 'macos';
    }

    final installId = await _getOrCreateInstallId();
    final identitySource = _isWeakRawId(rawId, deviceType) ? installId : rawId;

    _cached = {
      'deviceId': _stableDeviceId(
        deviceType: deviceType,
        rawId: identitySource,
      ),
      'deviceType': deviceType,
    };
    return _cached!;
  }
}
