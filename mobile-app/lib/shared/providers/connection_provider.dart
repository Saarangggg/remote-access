import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../services/storage_service.dart';

// ── Connection Status ─────────────────────────────────────────────────────────
enum ConnectionStatus { disconnected, connecting, connected, error }

// ── Connection State ──────────────────────────────────────────────────────────
class ConnectionState {
  final ConnectionStatus status;
  final String? error;
  final Map<String, dynamic>? deviceInfo;

  const ConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.error,
    this.deviceInfo,
  });

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isConnecting => status == ConnectionStatus.connecting;

  ConnectionState copyWith({
    ConnectionStatus? status,
    String? error,
    Map<String, dynamic>? deviceInfo,
  }) =>
      ConnectionState(
        status: status ?? this.status,
        error: error,
        deviceInfo: deviceInfo ?? this.deviceInfo,
      );
}

// ── Socket Service ────────────────────────────────────────────────────────────
class SocketService {
  io.Socket? _socket;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _deviceStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _clipboardController = StreamController<Map<String, dynamic>>.broadcast();
  final _screenFrameController = StreamController<String>.broadcast();
  final _fileProgressController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onDeviceStatus => _deviceStatusController.stream;
  Stream<Map<String, dynamic>> get onClipboardUpdate => _clipboardController.stream;
  Stream<String> get onScreenFrame => _screenFrameController.stream;
  Stream<Map<String, dynamic>> get onFileProgress => _fileProgressController.stream;

  io.Socket? get socket => _socket;

  void connect(String baseUrl, String token) {
    disconnect();

    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
      _statusController.add(ConnectionStatus.connected);
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
      _statusController.add(ConnectionStatus.disconnected);
    });

    _socket!.onConnectError((e) {
      debugPrint('Socket connect error: $e');
      _statusController.add(ConnectionStatus.error);
    });

    _socket!.on('device:status', (data) {
      if (data is Map) {
        _deviceStatusController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('clipboard:update', (data) {
      if (data is Map) {
        _clipboardController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('screen:frame', (data) {
      if (data is Map && data['data'] != null) {
        _screenFrameController.add(data['data'] as String);
      }
    });

    _socket!.on('file:progress', (data) {
      if (data is Map) {
        _fileProgressController.add(Map<String, dynamic>.from(data));
      }
    });

    _statusController.add(ConnectionStatus.connecting);
    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  void startScreenStream({int fps = 15, String quality = 'medium', int monitorIndex = 0}) {
    emit('screen:start', {'fps': fps, 'quality': quality, 'monitorIndex': monitorIndex});
  }

  void stopScreenStream() {
    emit('screen:stop');
  }

  void sendMouseEvent(Map<String, dynamic> data) {
    emit('input:mouse', data);
  }

  void sendKeyEvent(Map<String, dynamic> data) {
    emit('input:key', data);
  }

  void setClipboard(String text) {
    emit('clipboard:set', {'text': text});
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _deviceStatusController.close();
    _clipboardController.close();
    _screenFrameController.close();
    _fileProgressController.close();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.dispose);
  return service;
});

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  final SocketService _socketService;
  late final StreamSubscription<ConnectionStatus> _statusSub;

  ConnectionNotifier(this._socketService) : super(const ConnectionState()) {
    _statusSub = _socketService.onStatusChanged.listen((status) {
      state = state.copyWith(status: status);
    });
  }

  Future<void> connect(DeviceConfig device) async {
    state = const ConnectionState(status: ConnectionStatus.connecting);
    try {
      _socketService.connect(device.baseUrl, device.accessToken);
    } catch (e) {
      state = ConnectionState(
        status: ConnectionStatus.error,
        error: e.toString(),
      );
    }
  }

  void disconnect() {
    _socketService.disconnect();
    state = const ConnectionState(status: ConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _statusSub.cancel();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  final socket = ref.watch(socketServiceProvider);
  return ConnectionNotifier(socket);
});
