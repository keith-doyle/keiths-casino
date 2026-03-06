import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import '../widgets/playing_card_widget.dart';

class BlackjackScreen extends StatefulWidget {
  const BlackjackScreen({super.key});

  @override
  State<BlackjackScreen> createState() => _BlackjackScreenState();
}

class _BlackjackScreenState extends State<BlackjackScreen> {
  final BlackjackWsService _ws = BlackjackWsService();
  StreamSubscription? _sub;

  String? _gameId;

  List<String> _playerCards = [];
  List<String> _dealerCards = [];
  int _playerTotal = 0;
  int _dealerTotal = 0;

  String _status = 'Connecting...';
  bool _gameOver = false;
  bool _dealerRevealed = false;
  bool _busy = true;

  bool _savedThisHand = false;

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final roomId = uid ?? "testroom";

    _ws.connectToBlackjack(roomId: roomId);

    _sub = _ws.stream?.listen(
          (event) async {
        // WebSocket channel gives dynamic; usually String
        final text = event is String ? event : event.toString();

        Map<String, dynamic> msg;
        try {
          msg = (jsonDecode(text) as Map).cast<String, dynamic>();
        } catch (_) {
          // Non-JSON message
          if (!mounted) return;
          setState(() {
            _status = text;
            _busy = false;
          });
          return;
        }

        final type = msg["type"];

        // System / error messages
        if (type == "system") {
          if (!mounted) return;
          setState(() {
            _status = (msg["status"] ?? "").toString();
          });

          // After connection message, auto-deal
          _sendAction("deal");
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

        // Game state payload
        if (type == "state") {
          if (!mounted) return;

          setState(() {
            _gameId = msg["game_id"] as String?;

            _playerCards = List<String>.from((msg["player_cards"] ?? []) as List);
            _dealerCards = List<String>.from((msg["dealer_cards"] ?? []) as List);

            _playerTotal = (msg["player_total"] ?? 0) as int;
            _dealerTotal = (msg["dealer_total"] ?? 0) as int;

            _status = (msg["status"] ?? "").toString();
            _gameOver = (msg["game_over"] ?? false) as bool;
            _dealerRevealed = (msg["dealer_revealed"] ?? false) as bool;

            _busy = false;
          });

          // Save once when hand ends
          if (_gameOver && !_savedThisHand) {
            _savedThisHand = true;
            try {
              await _saveMatchAndStats(msg["result"]);
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _status = "Match/stat save failed: $e";
              });
            }
          }

          return;
        }

        // Unknown message type
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

    // We’ll wait for the "system" message before dealing.
  }

  void _sendAction(String action) {
    setState(() => _busy = true);

    if (action == "deal") {
      _savedThisHand = false;
      _gameId = null;
    }

    _ws.sendJson({
      "type": "action",
      "action": action,
      "game_id": _gameId, // can be null for deal
    });
  }

  Future<void> _saveMatchAndStats(dynamic result) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not signed in");

    final resultStr = (result is String) ? result : null;
    if (resultStr == null) throw Exception("Missing result from backend payload");

    if (resultStr != 'Win' && resultStr != 'Loss' && resultStr != 'Push') {
      throw Exception('Invalid result value: $resultStr');
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final matchesRef = userRef.collection('matches');
    final statsRef = userRef.collection('stats').doc('blackjack');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Reads first
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

      // Writes after reads
      final matchDoc = matchesRef.doc();
      tx.set(matchDoc, {
        'gameType': 'Blackjack',
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
    final theme = Theme.of(context);
    final dealerTotalText = _dealerRevealed ? _dealerTotal.toString() : '??';

    final canPlayMove = !_busy && !_gameOver && _gameId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Blackjack')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Text('Dealer', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: List.generate(
                      _dealerCards.length,
                          (i) => PlayingCardWidget(
                        cardId: _dealerCards[i],
                        faceDown: !_dealerRevealed && i != 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Dealer total: $dealerTotalText'),
                ],
              ),
            ),
            const Spacer(),
            Center(
              child: Column(
                children: [
                  Text('You', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: _playerCards.map((c) => PlayingCardWidget(cardId: c)).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text('Your total: $_playerTotal'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Status: $_status'),
            const SizedBox(height: 16),
            if (_gameOver)
              FilledButton(
                onPressed: _busy ? null : () => _sendAction("deal"),
                child: _busy ? const Text('Working...') : const Text('Play again'),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton(
                    onPressed: canPlayMove ? () => _sendAction("hit") : null,
                    child: const Text('Hit'),
                  ),
                  FilledButton(
                    onPressed: canPlayMove ? () => _sendAction("stand") : null,
                    child: const Text('Stand'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
