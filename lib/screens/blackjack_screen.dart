import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/playing_card_widget.dart';

class BlackjackScreen extends StatefulWidget {
  const BlackjackScreen({super.key});

  @override
  State<BlackjackScreen> createState() => _BlackjackScreenState();
}

class _BlackjackScreenState extends State<BlackjackScreen> {
  List<String> _playerCards = [];
  List<String> _dealerCards = [];
  int _playerTotal = 0;
  int _dealerTotal = 0;
  String _status = 'Dealing first hand...';
  bool _gameOver = false;
  bool _dealerRevealed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callAction('deal');
    });
  }

  Future<void> _callAction(String action) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final uri = Uri.parse('http://10.0.2.2:8000/blackjack/$action');
      final res = await http.post(uri);

      final data = jsonDecode(res.body);
      setState(() {
        _playerCards = List<String>.from(data['player_cards']);
        _dealerCards = List<String>.from(data['dealer_cards']);
        _playerTotal = data['player_total'];
        _dealerTotal = data['dealer_total'];
        _status = data['status'];
        _gameOver = data['game_over'];
        _dealerRevealed = data['dealer_revealed'];
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dealerTotalText = _dealerRevealed ? _dealerTotal.toString() : '??';

    return Scaffold(
      appBar: AppBar(title: const Text('Blackjack')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Text('Dealer',
                      style: theme.textTheme.titleMedium),
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
                  Text('You',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children:
                    _playerCards.map((c) => PlayingCardWidget(cardId: c)).toList(),
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
                onPressed: () => _callAction('deal'),
                child: const Text('Play again'),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton(
                    onPressed: () => _callAction('hit'),
                    child: const Text('Hit'),
                  ),
                  FilledButton(
                    onPressed: () => _callAction('stand'),
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
