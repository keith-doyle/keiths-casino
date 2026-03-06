import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BlackjackWsService {
  WebSocketChannel? _channel;

  static const String _baseWs = 'ws://16.170.162.140:8000';
// static const String _baseWs = 'ws://10.0.2.2:8000'; for local hosting
  void connectToRoom({required String roomId}) {
    final uri = Uri.parse('$_baseWs/ws/room/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }

  void connectToBlackjack({required String roomId}) {
    final uri = Uri.parse('$_baseWs/ws/blackjack/$roomId');
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