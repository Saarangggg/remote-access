import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds all saved device configurations
class DeviceConfig {
  final String deviceId;
  final String deviceName;
  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime pairedAt;

  const DeviceConfig({
    required this.deviceId,
    required this.deviceName,
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'pairedAt': pairedAt.toIso8601String(),
      };

  factory DeviceConfig.fromJson(Map<String, dynamic> json) => DeviceConfig(
        deviceId: json['deviceId'],
        deviceName: json['deviceName'],
        baseUrl: json['baseUrl'],
        accessToken: json['accessToken'],
        refreshToken: json['refreshToken'],
        pairedAt: DateTime.parse(json['pairedAt']),
      );

  DeviceConfig copyWith({
    String? accessToken,
    String? refreshToken,
  }) =>
      DeviceConfig(
        deviceId: deviceId,
        deviceName: deviceName,
        baseUrl: baseUrl,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        pairedAt: pairedAt,
      );
}

class StorageService {
  static const _devicesKey = 'trusted_devices';
  static const _activeDeviceKey = 'active_device_id';
  static const _settingsKey = 'app_settings';

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  // ── Devices ────────────────────────────────────────────────────────────────
  List<DeviceConfig> getDevices() {
    final raw = _prefs.getStringList(_devicesKey) ?? [];
    return raw.map((s) => DeviceConfig.fromJson(jsonDecode(s))).toList();
  }

  Future<void> saveDevice(DeviceConfig device) async {
    final devices = getDevices();
    final idx = devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (idx >= 0) {
      devices[idx] = device;
    } else {
      devices.add(device);
    }
    await _prefs.setStringList(
      _devicesKey,
      devices.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  Future<void> removeDevice(String deviceId) async {
    final devices = getDevices().where((d) => d.deviceId != deviceId).toList();
    await _prefs.setStringList(
      _devicesKey,
      devices.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  // ── Active Device ──────────────────────────────────────────────────────────
  String? getActiveDeviceId() => _prefs.getString(_activeDeviceKey);

  Future<void> setActiveDevice(String deviceId) async {
    await _prefs.setString(_activeDeviceKey, deviceId);
  }

  DeviceConfig? getActiveDevice() {
    final id = getActiveDeviceId();
    if (id == null) return null;
    return getDevices().where((d) => d.deviceId == id).firstOrNull;
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  Map<String, dynamic> getSettings() {
    final raw = _prefs.getString(_settingsKey) ?? '{}';
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveSetting(String key, dynamic value) async {
    final settings = getSettings();
    settings[key] = value;
    await _prefs.setString(_settingsKey, jsonEncode(settings));
  }

  T getSetting<T>(String key, T defaultValue) {
    final settings = getSettings();
    return (settings[key] as T?) ?? defaultValue;
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Initialize with SharedPreferences');
});

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});
