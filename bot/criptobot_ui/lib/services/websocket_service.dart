import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnectTimer;
  bool _estaActivo = false;

  Stream<Map<String, dynamic>> get eventos => _eventController.stream;

  void conectar() {
    desconectar();
    _estaActivo = true;
    final wsUrl = ApiService.baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    try {
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/live'));
      _channel?.stream.listen(
        (data) {
          try {
            final parsed = jsonDecode(data.toString());
            if (parsed is Map<String, dynamic>) {
              _eventController.add(parsed);
            }
          } catch (_) {}
        },
        onError: (err) {
          if (_estaActivo) {
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(const Duration(seconds: 5), conectar);
          }
        },
        onDone: () {
          if (_estaActivo) {
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(const Duration(seconds: 5), conectar);
          }
        },
      );
    } catch (_) {}
  }

  void desconectar() {
    _estaActivo = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    desconectar();
    _eventController.close();
  }
}
