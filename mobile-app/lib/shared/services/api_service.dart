import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

class ApiService {
  late Dio _dio;
  String? _baseUrl;
  String? _accessToken;

  Dio get dio => _dio;

  void configure(String baseUrl, String accessToken) {
    _baseUrl = baseUrl;
    _accessToken = accessToken;
    _dio = Dio(BaseOptions(
      baseUrl: '$baseUrl/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
    ));
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String deviceId,
    required String deviceName,
    required String baseUrl,
  }) async {
    final tempDio = Dio(BaseOptions(
      baseUrl: '$baseUrl/api',
      connectTimeout: const Duration(seconds: 15),
    ));
    final res = await tempDio.post('/auth/pair', data: {
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': 'android',
    });
    return res.data as Map<String, dynamic>;
  }

  // ── Device ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDeviceStatus() async {
    final res = await _dio.get('/device/status');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final res = await _dio.get('/device/info');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getDisplays() async {
    final res = await _dio.get('/device/displays');
    return (res.data as Map)['displays'] as List;
  }

  Future<void> openApp({String? appName, String? command}) async {
    await _dio.post('/device/open-app', data: {
      if (appName != null) 'appName': appName,
      if (command != null) 'command': command,
    });
  }

  Future<List<dynamic>> getInstalledApps() async {
    final res = await _dio.get('/device/apps');
    return (res.data as Map)['apps'] as List;
  }

  // ── Files ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listFiles(String path) async {
    final res = await _dio.get('/files', queryParameters: {'path': path});
    return res.data as Map<String, dynamic>;
  }

  Future<void> uploadFiles(
    String path,
    List<String> filePaths, {
    ProgressCallback? onProgress,
  }) async {
    final formData = FormData();
    for (final filePath in filePaths) {
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(filePath),
      ));
    }
    await _dio.post(
      '/files/upload',
      data: formData,
      queryParameters: {'path': path},
      onSendProgress: onProgress,
    );
  }

  Future<Response> downloadFile(String filePath) async {
    return _dio.get(
      '/files/download',
      queryParameters: {'path': filePath},
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<void> deleteFile(String path) async {
    await _dio.delete('/files/delete', data: {'path': path});
  }

  Future<void> renameFile(String path, String newName) async {
    await _dio.patch('/files/rename', data: {'path': path, 'newName': newName});
  }

  Future<void> moveFile(String from, String to) async {
    await _dio.patch('/files/move', data: {'from': from, 'to': to});
  }

  Future<void> createFolder(String path) async {
    await _dio.post('/files/mkdir', data: {'path': path});
  }

  Future<Map<String, dynamic>> searchFiles(String query, {String? path}) async {
    final res = await _dio.get('/files/search', queryParameters: {
      'q': query,
      if (path != null) 'path': path,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────
  Future<String> getClipboard() async {
    final res = await _dio.get('/clipboard');
    return (res.data as Map)['text'] as String? ?? '';
  }

  Future<void> setClipboard(String text) async {
    await _dio.post('/clipboard/sync', data: {'text': text});
  }

  // ── Auth Devices ──────────────────────────────────────────────────────────
  Future<List<dynamic>> getTrustedDevices() async {
    final res = await _dio.get('/auth/devices');
    return (res.data as Map)['devices'] as List;
  }

  Future<void> removeDevice(String deviceId) async {
    await _dio.delete('/auth/devices/$deviceId');
  }

  Future<void> logoutAll() async {
    await _dio.post('/auth/logout-all');
  }
}

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});
