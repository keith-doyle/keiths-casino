import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BlackjackWsService {
  WebSocketChannel? _channel;

  void connectToRoom({required String roomId}) {
    final uri = Uri.parse('ws://10.0.2.2:8000/ws/room/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }

  Stream<dynamic>? get stream => _channel?.stream;

  void join({required String playerId, required String playerName}) {
    sendJson({
      "type": "join",
      "player_id": playerId,
      "player_name": playerName,
    });
  }

  void sendJson(Map<String, dynamic> payload) {
    final msg = jsonEncode(payload);
    _channel?.sink.add(msg);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
