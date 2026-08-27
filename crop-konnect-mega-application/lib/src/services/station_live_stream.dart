import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/sensor_reading.dart';

class StationLiveStream {
  StationLiveStream({
    required String baseUrl,
    required String deviceId,
  })  : _baseUrl = baseUrl,
        _deviceId = deviceId;

  final String _baseUrl;
  final String _deviceId;

  StreamController<SensorReading>? _controller;
  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  Stream<SensorReading> connect() {
    _controller ??= StreamController<SensorReading>.broadcast(
      onListen: _ensureConnected,
      onCancel: _closeSocketIfUnused,
    );
    _ensureConnected();
    return _controller!.stream;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _controller?.close();
    _controller = null;
  }

  Future<void> _ensureConnected() async {
    if (_disposed || _controller == null || _channel != null) {
      return;
    }

    try {
      final wsUrl = _buildWebSocketUrl();
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;

      _socketSubscription = channel.stream.listen(
        _handleMessage,
        onDone: _scheduleReconnect,
        onError: (_, __) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  String _buildWebSocketUrl() {
    final base = Uri.parse(_baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws/stations/$_deviceId',
    );
    return wsUri.toString();
  }

  void _handleMessage(dynamic message) {
    if (_controller == null || _disposed) {
      return;
    }

    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      if (decoded['type'] != 'reading.created') {
        return;
      }

      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) {
        return;
      }

      _controller!.add(SensorReading.fromJson(payload));
    } catch (_) {
      // Ignore malformed stream payloads and wait for the next valid update.
    }
  }

  void _scheduleReconnect() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel = null;
    if (_disposed || _controller == null) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _ensureConnected);
  }

  void _closeSocketIfUnused() {
    if (_controller != null && _controller!.hasListener) {
      return;
    }
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel?.sink.close();
    _channel = null;
  }
}
