import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fyp_app/widgets/playing_card_widget.dart';

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
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    'J',
    'Q',
    'K',
    'A',
  ];
  static const _suits = ['H', 'D', 'C', 'S'];
//Starts non-persistent poker tutorial round
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
//Progress tutorial and update lessons
  void _advancePhase() {
    if (!_roundActive || _roundOver) return;

    final deck = _freshDeck()
      ..removeWhere(
            (c) =>
        _playerCards.contains(c) ||
            _opponentCards.contains(c) ||
            _communityCards.contains(c),
      );

    setState(() {
      if (_phase == 'preflop') {
        _communityCards.addAll([
          deck.removeAt(0),
          deck.removeAt(0),
          deck.removeAt(0),
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
//Practice only showdown
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
//Tutorial check
  void _check() {
    if (!_roundActive || _roundOver) return;
    setState(() {
      _status =
      'You checked. Checking means you pass the action without adding chips.';
    });
    _advancePhase();
  }
//Tutorial raise
  void _raise() {
    if (!_roundActive || _roundOver) return;
    setState(() {
      _pot += 100;
      _status =
      'You raised. Raising increases pressure and builds the pot when your hand is strong.';
    });
    _advancePhase();
  }
//Tutorial fold
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
//Generates phase specific tutorial explanations
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
      case 'folded':
        return 'Fold lesson';
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
      case 'folded':
        return 'Folding ends your hand immediately. It is the safest option when continuing would risk more chips with a weak holding.';
      default:
        return 'Start a tutorial round to learn poker phase by phase.';
    }
  }

  Color _phaseColor() {
    switch (_phase) {
      case 'preflop':
        return Colors.blue.shade300;
      case 'flop':
        return Colors.green.shade300;
      case 'turn':
        return Colors.orange.shade300;
      case 'river':
        return Colors.purple.shade300;
      case 'showdown':
        return Colors.amber.shade300;
      case 'folded':
        return Colors.red.shade300;
      default:
        return Colors.white70;
    }
  }

  Widget _pill(String text, {Color? color}) {
    final fg = color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (color ?? Colors.white).withOpacity(0.22),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _panel(String title, Widget child, {Widget? trailing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _tableSurface({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.25,
          colors: [
            const Color(0xFF14532D),
            const Color(0xFF0F3F23),
            Colors.black.withOpacity(0.92),
          ],
        ),
        border: Border.all(color: Colors.white12, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _cardRow(
      List<String> cards, {
        String emptyText = 'No cards yet',
        bool hidden = false,
      }) {
    if (cards.isEmpty) {
      return Text(
        emptyText,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: cards.map((card) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: PlayingCardWidget(
              cardId: card,
              faceDown: hidden,
              width: 58,
              height: 86,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _lessonBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _phaseColor().withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _phaseColor().withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _lessonTitle(),
            style: TextStyle(
              color: _phaseColor(),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _lessonBody(),
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        _status,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _opponentSeat() {
    return _panel(
      'Opponent',
      Column(
        children: [
          _cardRow(
            _roundOver ? _opponentCards : List.filled(2, '??'),
            emptyText: 'Opponent waiting',
          ),
          const SizedBox(height: 8),
          Text(
            _roundOver
                ? 'Cards revealed at showdown'
                : 'Opponent cards stay hidden until the hand ends',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: _pill(
        _roundOver ? 'REVEALED' : 'HIDDEN',
        color: _roundOver ? Colors.orange.shade300 : Colors.white70,
      ),
    );
  }

  Widget _communityPanel() {
    return _panel(
      'Community Cards',
      Column(
        children: [
          _cardRow(_communityCards),
          const SizedBox(height: 10),
          Text(
            _communityCards.isEmpty
                ? 'Shared cards will appear as the hand progresses.'
                : 'These are shared by both players to build the best 5-card hand.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: _pill(
        _phase.toUpperCase(),
        color: _phaseColor(),
      ),
    );
  }

  Widget _playerPanel() {
    return _panel(
      'Your Hole Cards',
      Column(
        children: [
          _cardRow(_playerCards),
          const SizedBox(height: 10),
          const Text(
            'These 2 private cards belong only to you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: _pill('YOU', color: Colors.green.shade300),
    );
  }

  Widget _buildActionButtons() {
    final disabled = !_roundActive || _roundOver;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: disabled ? null : _check,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                icon: const Icon(Icons.check),
                label: const Text('Check'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: disabled ? null : _raise,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
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
            onPressed: disabled ? null : _fold,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              foregroundColor: Colors.red.shade200,
              side: BorderSide(color: Colors.red.shade200.withOpacity(0.55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            icon: const Icon(Icons.close),
            label: const Text('Fold'),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
    if (!_roundActive && !_roundOver) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _startRound,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Tutorial Round'),
        ),
      );
    }

    if (_roundActive) {
      return _buildActionButtons();
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _startRound,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        icon: const Icon(Icons.replay),
        label: const Text('Play Tutorial Again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roundStateText = _roundOver
        ? (_phase == 'folded' ? 'Hand ended by fold' : 'Hand complete')
        : (_roundActive ? 'Tutorial hand active' : 'Ready to begin');

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
                alignment: WrapAlignment.center,
                children: [
                  _pill('Mode: Tutorial', color: Colors.amber.shade300),
                  _pill('Phase: ${_phase.toUpperCase()}', color: _phaseColor()),
                  _pill('Practice Coins: $_coins'),
                  _pill('Pot: $_pot'),
                ],
              ),
              const SizedBox(height: 14),
              _lessonBanner(),
              const SizedBox(height: 14),
              _statusBanner(),
              const SizedBox(height: 16),
              _tableSurface(
                child: Column(
                  children: [
                    _opponentSeat(),
                    const SizedBox(height: 14),
                    _communityPanel(),
                    const SizedBox(height: 14),
                    _playerPanel(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _panel(
                'Tutorial Flow',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roundStateText,
                      style: TextStyle(
                        color: _phaseColor(),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use Check to continue without building the pot. Use Raise to add pressure and grow the pot. Use Fold to end the hand early.',
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildBottomAction(),
            ],
          ),
        ),
      ),
    );
  }
}