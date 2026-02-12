import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  Map<String, String>? _cached;

  Future<Map<String, String>> getDeviceInfo() async {
    if (_cached != null) return _cached!;

    if (kIsWeb) {
      _cached = {
        'deviceId': 'web',
        'deviceType': 'web',
      };
      return _cached!;
    }

    if (Platform.isAndroid) {
      final android = await _deviceInfo.androidInfo;
      _cached = {
        'deviceId': android.id,
        'deviceType': 'android',
      };
      return _cached!;
    }

    if (Platform.isIOS) {
      final ios = await _deviceInfo.iosInfo;
      _cached = {
        'deviceId': ios.identifierForVendor ?? 'ios',
        'deviceType': 'ios',
      };
      return _cached!;
    }

    if (Platform.isWindows) {
      final windows = await _deviceInfo.windowsInfo;
      _cached = {
        'deviceId': windows.deviceId,
        'deviceType': 'windows',
      };
      return _cached!;
    }

    if (Platform.isMacOS) {
      final mac = await _deviceInfo.macOsInfo;
      _cached = {
        'deviceId': mac.systemGUID ?? 'macos',
        'deviceType': 'macos',
      };
      return _cached!;
    }

    _cached = {
      'deviceId': 'unknown',
      'deviceType': 'unknown',
    };
    return _cached!;
  }
}
