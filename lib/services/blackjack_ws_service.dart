import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BlackjackWsService {
  WebSocketChannel? _channel;

  void connect({required String roomId}) {
    //final uri = Uri.parse('ws://172.20.10.2:8000/ws/blackjack/$roomId'); for phone demoing
    final uri = Uri.parse('ws://10.0.2.2:8000/ws/blackjack/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }

  Stream<dynamic>? get stream => _channel?.stream;

  void sendJson(Map<String, dynamic> payload) {
    final msg = jsonEncode(payload);
    _channel?.sink.add(msg);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
