import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import '../widgets/playing_card_widget.dart';

class BlackjackTableScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;

  const BlackjackTableScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<BlackjackTableScreen> createState() => _BlackjackTableScreenState();
}

class _BlackjackTableScreenState extends State<BlackjackTableScreen> {
  final BlackjackWsService _ws = BlackjackWsService();
  StreamSubscription? _sub;

  List<String> _dealerCards = [];
  int? _dealerTotal;

  List<Map<String, dynamic>> _players = [];

  String _status = 'Connecting...';
  String? _hostPlayerId;
  String? _turnPlayerId;

  bool _gameStarted = false;
  bool _gameOver = false;
  bool _dealerRevealed = false;
  bool _busy = true;

  bool _savedThisRound = false;

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() {
    _ws.connectToBlackjackTable(roomId: widget.roomId);

    _sub = _ws.stream?.listen(
          (event) async {
        final text = event is String ? event : event.toString();

        Map<String, dynamic> msg;
        try {
          msg = (jsonDecode(text) as Map).cast<String, dynamic>();
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _status = text;
            _busy = false;
          });
          return;
        }

        final type = msg["type"];

        if (type == "system") {
          _ws.join(
            playerId: widget.playerId,
            playerName: widget.playerName,
          );

          if (!mounted) return;
          setState(() {
            _status = (msg["status"] ?? "").toString();
            _busy = false;
          });
          return;
        }

        if (type == "error") {
          if (!mounted) return;
          setState(() {
            _status = (msg["status"] ?? "Unknown error").toString();
            _busy = false;
          });
          return;
        }

        if (type == "table_state") {
          final players = List<Map<String, dynamic>>.from(msg["players"] ?? []);

          if (!mounted) return;
          setState(() {
            _dealerCards = List<String>.from(msg["dealer_cards"] ?? []);
            _dealerTotal = msg["dealer_total"] as int?;
            _players = players;

            _status = (msg["status"] ?? "").toString();
            _hostPlayerId = msg["host_player_id"]?.toString();
            _turnPlayerId = msg["turn_player_id"]?.toString();

            _gameStarted = (msg["game_started"] ?? false) as bool;
            _gameOver = (msg["game_over"] ?? false) as bool;
            _dealerRevealed = (msg["dealer_revealed"] ?? false) as bool;

            _busy = false;
          });

          if (!_gameStarted) {
            _savedThisRound = false;
          }

          if (_gameOver && !_savedThisRound) {
            final me = _myPlayer;
            final result = me?["result"]?.toString();

            if (result == "Win" || result == "Loss" || result == "Push") {
              _savedThisRound = true;
              try {
                await _saveMatchAndStats(result!);
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _status = "Match/stat save failed: $e";
                });
              }
            }
          }

          return;
        }

        if (!mounted) return;
        setState(() {
          _status = "Unknown message: $msg";
          _busy = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _status = "WS error: $e";
          _busy = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _status = "Disconnected";
          _busy = false;
        });
      },
    );
  }

  Map<String, dynamic>? get _myPlayer {
    try {
      return _players.firstWhere((p) => p["id"] == widget.playerId);
    } catch (_) {
      return null;
    }
  }

  bool get _isHost => _hostPlayerId == widget.playerId;
  bool get _isMyTurn => _turnPlayerId == widget.playerId;

  Future<void> _saveMatchAndStats(String resultStr) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not signed in");

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final matchesRef = userRef.collection('matches');
    final statsRef = userRef.collection('stats').doc('blackjack');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final statsSnap = await tx.get(statsRef);

      int gamesPlayed = 0;
      int wins = 0;
      int losses = 0;
      int pushes = 0;

      if (statsSnap.exists) {
        final existing = statsSnap.data() as Map<String, dynamic>;
        gamesPlayed = ((existing['gamesPlayed'] ?? 0) as num).toInt();
        wins = ((existing['wins'] ?? 0) as num).toInt();
        losses = ((existing['losses'] ?? 0) as num).toInt();
        pushes = ((existing['pushes'] ?? 0) as num).toInt();
      }

      gamesPlayed += 1;
      if (resultStr == 'Win') wins += 1;
      if (resultStr == 'Loss') losses += 1;
      if (resultStr == 'Push') pushes += 1;

      final matchDoc = matchesRef.doc();
      tx.set(matchDoc, {
        'gameType': 'Blackjack Multiplayer',
        'result': resultStr,
        'playedAt': FieldValue.serverTimestamp(),
      });

      tx.set(statsRef, {
        'gameType': 'Blackjack',
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'losses': losses,
        'pushes': pushes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dealerTotalText = _dealerRevealed
        ? (_dealerTotal?.toString() ?? '-')
        : '??';

    final canStart = !_gameStarted && !_busy && _isHost && _players.length >= 2;
    final canRestart = _gameOver && !_busy && _isHost && _players.length >= 2;
    final canPlay = _gameStarted && !_gameOver && !_busy && _isMyTurn;

    return Scaffold(
      appBar: AppBar(
        title: Text('Blackjack Table (${widget.roomId})'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Dealer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: List.generate(
                        _dealerCards.length,
                            (i) => PlayingCardWidget(
                          cardId: _dealerCards[i],
                          faceDown: !_dealerRevealed && i != 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Dealer total: $dealerTotalText'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _players.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = _players[i];
                  final isYou = p["id"] == widget.playerId;
                  final isTurn = p["id"] == _turnPlayerId;

                  final cards = List<String>.from(p["cards"] ?? []);
                  final total = p["total"] ?? 0;
                  final result = p["result"]?.toString();

                  return Card(
                    color: isYou ? Colors.indigo.withValues(alpha: 0.08) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${p["name"]}${isYou ? " (YOU)" : ""}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (p["id"] == _hostPlayerId)
                                const Text(
                                  'HOST',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                              if (isTurn) ...[
                                const SizedBox(width: 12),
                                const Text(
                                  'TURN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: cards
                                .map((c) => PlayingCardWidget(
                              cardId: c,
                              width: 60,
                              height: 90,
                            ))
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                          Text('Total: $total'),
                          const SizedBox(height: 4),
                          Text(
                            'Result: ${result ?? "-"}',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _status,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (!_gameStarted)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canStart ? _ws.sendStart : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _players.length < 2
                        ? 'Need 2 players to start'
                        : (_isHost ? 'Start Game' : 'Waiting for host to start'),
                  ),
                ),
              )
            else if (_gameOver)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canRestart ? _ws.sendStart : null,
                  icon: const Icon(Icons.replay),
                  label: Text(
                    _isHost ? 'Start New Round' : 'Waiting for host to restart',
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: canPlay ? () => _ws.sendAction("hit") : null,
                      child: const Text('Hit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canPlay ? () => _ws.sendAction("stand") : null,
                      child: const Text('Stand'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}