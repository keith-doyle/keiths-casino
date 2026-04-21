import 'dart:math';
import 'package:flutter/material.dart';

class TutorialPokerScreen extends StatefulWidget {
  const TutorialPokerScreen({super.key});

  @override
  State<TutorialPokerScreen> createState() => _TutorialPokerScreenState();
}

class _TutorialPokerScreenState extends State<TutorialPokerScreen> {
  final Random _rand = Random();

  String _phase = 'preflop';
  String _status = 'Press Start Tutorial Round';
  bool _roundActive = false;
  bool _roundOver = false;

  List<String> _playerCards = [];
  List<String> _opponentCards = [];
  List<String> _communityCards = [];

  int _coins = 1000;
  int _pot = 0;

  static const _ranks = [
    '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'
  ];
  static const _suits = ['H', 'D', 'C', 'S'];

  List<String> _freshDeck() {
    final deck = <String>[];
    for (final r in _ranks) {
      for (final s in _suits) {
        deck.add('$r$s');
      }
    }
    deck.shuffle(_rand);
    return deck;
  }

  int _cardValue(String card) {
    final rank = card.substring(0, card.length - 1);
    final index = _ranks.indexOf(rank);
    return index < 0 ? 0 : index + 2;
  }

  int _simpleScore(List<String> cards) {
    return cards.map(_cardValue).fold(0, (a, b) => a + b);
  }

  void _startRound() {
    final deck = _freshDeck();

    setState(() {
      _playerCards = [deck.removeAt(0), deck.removeAt(0)];
      _opponentCards = [deck.removeAt(0), deck.removeAt(0)];
      _communityCards = [];
      _phase = 'preflop';
      _status = 'Preflop: you have 2 private hole cards.';
      _roundActive = true;
      _roundOver = false;
      _pot = 20;
    });
  }

  void _advancePhase() {
    if (!_roundActive || _roundOver) return;

    final deck = _freshDeck()
      ..removeWhere((c) =>
      _playerCards.contains(c) ||
          _opponentCards.contains(c) ||
          _communityCards.contains(c));

    setState(() {
      if (_phase == 'preflop') {
        _communityCards.addAll([
          deck.removeAt(0),
          deck.removeAt(0),
          deck.removeAt(0)
        ]);
        _phase = 'flop';
        _status =
        'Flop: 3 community cards are revealed. Everyone can use these cards.';
      } else if (_phase == 'flop') {
        _communityCards.add(deck.removeAt(0));
        _phase = 'turn';
        _status = 'Turn: the 4th community card is revealed.';
      } else if (_phase == 'turn') {
        _communityCards.add(deck.removeAt(0));
        _phase = 'river';
        _status = 'River: the 5th and final community card is revealed.';
      } else {
        _showdown();
      }
    });
  }

  void _showdown() {
    final playerAll = [..._playerCards, ..._communityCards];
    final opponentAll = [..._opponentCards, ..._communityCards];

    final playerScore = _simpleScore(playerAll);
    final opponentScore = _simpleScore(opponentAll);

    setState(() {
      _roundActive = false;
      _roundOver = true;
      _phase = 'showdown';

      if (playerScore >= opponentScore) {
        _coins += _pot;
        _status =
        'Showdown: you win. In real poker, players compare their best 5-card hand.';
      } else {
        _status =
        'Showdown: opponent wins. In real poker, the strongest 5-card hand takes the pot.';
      }
    });
  }

  void _check() {
    if (!_roundActive || _roundOver) return;
    setState(() {
      _status =
      'You checked. Checking means you pass the action without adding chips.';
    });
    _advancePhase();
  }

  void _raise() {
    if (!_roundActive || _roundOver) return;
    setState(() {
      _pot += 100;
      _status =
      'You raised. Raising increases pressure and builds the pot when your hand is strong.';
    });
    _advancePhase();
  }

  void _fold() {
    if (!_roundActive || _roundOver) return;
    setState(() {
      _roundActive = false;
      _roundOver = true;
      _phase = 'folded';
      _status =
      'You folded. Folding means giving up the hand instead of risking more chips.';
    });
  }

  String _lessonTitle() {
    switch (_phase) {
      case 'preflop':
        return 'Preflop lesson';
      case 'flop':
        return 'Flop lesson';
      case 'turn':
        return 'Turn lesson';
      case 'river':
        return 'River lesson';
      case 'showdown':
        return 'Showdown lesson';
      default:
        return 'Poker lesson';
    }
  }

  String _lessonBody() {
    switch (_phase) {
      case 'preflop':
        return 'You begin with 2 private hole cards. Only you can see them. Early decisions are based mostly on starting hand strength.';
      case 'flop':
        return 'The flop adds 3 shared community cards. Now both players can combine their hole cards with the board.';
      case 'turn':
        return 'The turn adds a 4th community card. Hands become clearer and stronger combinations often begin to appear.';
      case 'river':
        return 'The river is the final community card. After this, there are no more cards to come.';
      case 'showdown':
        return 'At showdown, the best 5-card poker hand wins. You do not have to use both hole cards.';
      default:
        return 'Start a tutorial round to learn poker phase by phase.';
    }
  }

  Widget _panel(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _cardRow(List<String> cards) {
    if (cards.isEmpty) {
      return const Text(
        'No cards yet',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cards
          .map(
            (c) => Container(
          width: 52,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            c,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      )
          .toList(),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutorial Poker'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _chip('Mode: Tutorial'),
                  _chip('Phase: ${_phase.toUpperCase()}'),
                  _chip('Practice Coins: $_coins'),
                  _chip('Pot: $_pot'),
                ],
              ),
              const SizedBox(height: 14),
              _panel(
                _lessonTitle(),
                Text(
                  _lessonBody(),
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _panel(
                'Table Status',
                Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _panel('Community Cards', _cardRow(_communityCards)),
              const SizedBox(height: 14),
              _panel('Your Hole Cards', _cardRow(_playerCards)),
              const SizedBox(height: 14),
              if (_roundOver) _panel('Opponent Cards', _cardRow(_opponentCards)),
              const SizedBox(height: 14),
              if (!_roundActive && !_roundOver)
                FilledButton.icon(
                  onPressed: _startRound,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Tutorial Round'),
                )
              else if (_roundActive)
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _check,
                            icon: const Icon(Icons.check),
                            label: const Text('Check'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _raise,
                            icon: const Icon(Icons.arrow_upward),
                            label: const Text('Raise'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _fold,
                        icon: const Icon(Icons.close),
                        label: const Text('Fold'),
                      ),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: _startRound,
                  icon: const Icon(Icons.replay),
                  label: const Text('Play Tutorial Again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}