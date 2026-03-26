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

  int _coins = 0;
  int _selectedBet = 10;

  @override
  void initState() {
    super.initState();
    _loadCoins();
    _connectAndListen();
  }

  Future<void> _loadCoins() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      final data = doc.data();
      if (!mounted) return;

      setState(() {
        _coins = ((data?['coins'] ?? 0) as num).toInt();
      });
    } catch (_) {}
  }

  void _connectAndListen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final roomId = uid ?? "testroom";

    _ws.connectToBlackjack(roomId: roomId);

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

        if (type == "state") {
          if (!mounted) return;

          setState(() {
            _gameId = msg["game_id"] as String?;

            _playerCards =
            List<String>.from((msg["player_cards"] ?? []) as List);
            _dealerCards =
            List<String>.from((msg["dealer_cards"] ?? []) as List);

            _playerTotal = (msg["player_total"] ?? 0) as int;
            _dealerTotal = (msg["dealer_total"] ?? 0) as int;

            _status = (msg["status"] ?? "").toString();
            _gameOver = (msg["game_over"] ?? false) as bool;
            _dealerRevealed = (msg["dealer_revealed"] ?? false) as bool;

            _busy = false;
          });

          if (_gameOver && !_savedThisHand) {
            _savedThisHand = true;
            try {
              await _saveMatchStatsAndCoins(msg["result"]);
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _status = "Match/stat/coin save failed: $e";
              });
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

  void _sendAction(String action) {
    setState(() => _busy = true);

    if (action == "deal") {
      if (_selectedBet > _coins) {
        setState(() {
          _busy = false;
          _status = "Not enough coins for that bet.";
        });
        return;
      }

      _savedThisHand = false;
      _gameId = null;
    }

    _ws.sendJson({
      "type": "action",
      "action": action,
      "game_id": _gameId,
    });
  }

  Future<void> _saveMatchStatsAndCoins(dynamic result) async {
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
      final userSnap = await tx.get(userRef);
      final statsSnap = await tx.get(statsRef);

      int gamesPlayed = 0;
      int wins = 0;
      int losses = 0;
      int pushes = 0;
      int coins = 0;

      if (statsSnap.exists) {
        final existing = statsSnap.data() as Map<String, dynamic>;
        gamesPlayed = ((existing['gamesPlayed'] ?? 0) as num).toInt();
        wins = ((existing['wins'] ?? 0) as num).toInt();
        losses = ((existing['losses'] ?? 0) as num).toInt();
        pushes = ((existing['pushes'] ?? 0) as num).toInt();
      }

      if (userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>;
        coins = ((userData['coins'] ?? 0) as num).toInt();
      }

      gamesPlayed += 1;
      if (resultStr == 'Win') wins += 1;
      if (resultStr == 'Loss') losses += 1;
      if (resultStr == 'Push') pushes += 1;

      if (resultStr == 'Win') coins += _selectedBet;
      if (resultStr == 'Loss') coins -= _selectedBet;

      if (coins < 0) coins = 0;

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

      tx.set(userRef, {
        'coins': coins,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _coins = coins;
        });
      }
    });
  }

  Widget _betChip(int amount) {
    final selected = _selectedBet == amount;

    return ChoiceChip(
      label: Text('$amount'),
      selected: selected,
      onSelected: _busy || (_gameId != null && !_gameOver)
          ? null
          : (_) {
        setState(() {
          _selectedBet = amount;
        });
      },
    );
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
    final canDeal = !_busy && (_gameId == null || _gameOver);

    return Scaffold(
      appBar: AppBar(title: const Text('Blackjack')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Coins: $_coins',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Bet: $_selectedBet',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                _betChip(10),
                _betChip(25),
                _betChip(50),
                _betChip(100),
              ],
            ),
            const SizedBox(height: 18),
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
                    children: _playerCards
                        .map((c) => PlayingCardWidget(cardId: c))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Text('Your total: $_playerTotal'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Status: $_status'),
            const SizedBox(height: 16),
            if (_gameOver || _gameId == null)
              FilledButton(
                onPressed: canDeal ? () => _sendAction("deal") : null,
                child: _busy
                    ? const Text('Working...')
                    : const Text('Deal Hand'),
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