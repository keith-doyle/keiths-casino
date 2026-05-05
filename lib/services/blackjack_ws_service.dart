import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

//Channel connection between front and backend
class BlackjackWsService {
  WebSocketChannel? _channel;

  static const String _baseWs = 'ws://16.170.162.140:8000';
//Connect to room, Lobby websocket
  void connectToRoom({required String roomId}) {
    final uri = Uri.parse('$_baseWs/ws/room/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }

  void connectToBlackjack({required String roomId}) {
    final uri = Uri.parse('$_baseWs/ws/blackjack/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }
//Connect to blackjack table, blackjack table websocket
  void connectToBlackjackTable({required String roomId}) {
    final uri = Uri.parse('$_baseWs/ws/blackjack_table/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }
//Connect to poker table, Poker Table Websocket
  void connectToPokerTable({required String roomId}) {
    final uri = Uri.parse('$_baseWs/ws/poker_table/$roomId');
    _channel = WebSocketChannel.connect(uri);
  }
//How ui listens to broadcasted backend updates on table state room state etc.
  Stream<dynamic>? get stream => _channel?.stream;

  void join({required String playerId, required String playerName}) {
    sendJson({
      "type": "join",
      "player_id": playerId,
      "player_name": playerName,
    });
  }

  void sendStart() {
    sendJson({
      "type": "start",
    });
  }
//Encodes user flutter actions to json
  void sendAction(String action) {
    sendJson({
      "type": "action",
      "action": action,
    });
  }
//Received payload from game state
  void sendJson(Map<String, dynamic> payload) {
    final msg = jsonEncode(payload);
    _channel?.sink.add(msg);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}