import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import '../widgets/playing_card_widget.dart';

class BlackjackTableScreen extends StatefulWidget {
  final String roomId;

  const BlackjackTableScreen({
    super.key,
    required this.roomId,
  });

  @override
  State<BlackjackTableScreen> createState() => _BlackjackTableScreenState();
}

class _BlackjackTableScreenState extends State<BlackjackTableScreen> {
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

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() {
    _ws.connectToBlackjack(roomId: widget.roomId);

    _sub = _ws.stream?.listen(
          (event) {
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
          });

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

        if (type == "state") {
          if (!mounted) return;

          setState(() {
            _gameId = msg["game_id"] as String?;

            _playerCards = List<String>.from(msg["player_cards"] ?? []);
            _dealerCards = List<String>.from(msg["dealer_cards"] ?? []);

            _playerTotal = (msg["player_total"] ?? 0) as int;
            _dealerTotal = (msg["dealer_total"] ?? 0) as int;

            _status = (msg["status"] ?? "").toString();
            _gameOver = (msg["game_over"] ?? false) as bool;
            _dealerRevealed = (msg["dealer_revealed"] ?? false) as bool;

            _busy = false;
          });

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
      _gameId = null;
    }

    _ws.sendJson({
      "type": "action",
      "action": action,
      "game_id": _gameId,
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
      appBar: AppBar(
        title: Text('Blackjack Table (${widget.roomId})'),
      ),
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
            if (_gameOver)
              FilledButton(
                onPressed: _busy ? null : () => _sendAction("deal"),
                child: _busy
                    ? const Text('Working...')
                    : const Text('Play again'),
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