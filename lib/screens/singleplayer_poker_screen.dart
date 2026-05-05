import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_app/widgets/playing_card_widget.dart';

class SingleplayerPokerScreen extends StatefulWidget {
  const SingleplayerPokerScreen({super.key});

  @override
  State<SingleplayerPokerScreen> createState() =>
      _SingleplayerPokerScreenState();
}

class _SingleplayerPokerScreenState extends State<SingleplayerPokerScreen> {
  final Random _rand = Random();

  String _phase = 'preflop';
  String _status = 'Press Start Round';
  bool _roundActive = false;
  bool _roundOver = false;
  bool _savingResult = false;

  List<String> _playerCards = [];
  List<String> _opponentCards = [];
  List<String> _communityCards = [];

  int _coins = 1000;
  int _pot = 0;
  int _playerBet = 0;
  int _opponentBet = 0;

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
    'A'
  ];
  static const _suits = ['H', 'D', 'C', 'S'];

  @override
  void initState() {
    super.initState();
    _loadCoins();
  }
//Creates local deck for solo poker
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
//Simplified solo scoring not full hand ranking
  int _cardValue(String card) {
    final rank = card.substring(0, card.length - 1);
    final index = _ranks.indexOf(rank);
    return index < 0 ? 0 : index + 2;
  }

  int _simpleScore(List<String> cards) {
    return cards.map(_cardValue).fold(0, (a, b) => a + b);
  }
//Loads persisted balance from db before joining poker table
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
//Starts a singleplayer poker round with initial cards and pot
  void _startRound() {
    if (_coins < 10) {
      setState(() {
        _status = 'You need at least 10 coins to start a poker round.';
      });
      return;
    }

    final deck = _freshDeck();

    setState(() {
      _playerCards = [deck.removeAt(0), deck.removeAt(0)];
      _opponentCards = [deck.removeAt(0), deck.removeAt(0)];
      _communityCards = [];
      _phase = 'preflop';
      _status = 'Round started. You can check, raise, or fold.';
      _roundActive = true;
      _roundOver = false;
      _savingResult = false;
      _playerBet = 10;
      _opponentBet = 10;
      _pot = 20;
    });
  }
//Persists singleplayer poker outcome
  Future<void> _saveSingleplayerPokerResult(String resultStr) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final matchesRef = userRef.collection('matches');
    final statsRef = userRef.collection('stats').doc('poker');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final statsSnap = await tx.get(statsRef);

      int persistedCoins = _coins;
      if (userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>;
        persistedCoins = ((userData['coins'] ?? _coins) as num).toInt();
      }

      int gamesPlayed = 0;
      int wins = 0;
      int losses = 0;
      int coinsWon = 0;
      int coinsLost = 0;
      int netCoins = 0;
      int currentWinStreak = 0;
      int bestWinStreak = 0;
      int highestPotSeen = 0;
      int singleplayerGames = 0;
      int multiplayerGames = 0;
      int singleplayerWins = 0;
      int multiplayerWins = 0;

      if (statsSnap.exists) {
        final existing = statsSnap.data() as Map<String, dynamic>;
        gamesPlayed = ((existing['gamesPlayed'] ?? 0) as num).toInt();
        wins = ((existing['wins'] ?? 0) as num).toInt();
        losses = ((existing['losses'] ?? 0) as num).toInt();
        coinsWon = ((existing['coinsWon'] ?? 0) as num).toInt();
        coinsLost = ((existing['coinsLost'] ?? 0) as num).toInt();
        netCoins = ((existing['netCoins'] ?? 0) as num).toInt();
        currentWinStreak =
            ((existing['currentWinStreak'] ?? 0) as num).toInt();
        bestWinStreak = ((existing['bestWinStreak'] ?? 0) as num).toInt();
        highestPotSeen = ((existing['highestPotSeen'] ?? 0) as num).toInt();
        singleplayerGames =
            ((existing['singleplayerGames'] ?? 0) as num).toInt();
        multiplayerGames =
            ((existing['multiplayerGames'] ?? 0) as num).toInt();
        singleplayerWins =
            ((existing['singleplayerWins'] ?? 0) as num).toInt();
        multiplayerWins =
            ((existing['multiplayerWins'] ?? 0) as num).toInt();
      }

      gamesPlayed += 1;
      singleplayerGames += 1;

      final coinDelta = resultStr == 'Win' ? (_pot - _playerBet) : -_playerBet;

      int newCoins = persistedCoins + coinDelta;
      if (newCoins < 0) newCoins = 0;

      if (resultStr == 'Win') {
        wins += 1;
        singleplayerWins += 1;
        if (coinDelta > 0) {
          coinsWon += coinDelta;
        }
        currentWinStreak += 1;
      } else {
        losses += 1;
        coinsLost += _playerBet;
        currentWinStreak = 0;
      }

      if (currentWinStreak > bestWinStreak) {
        bestWinStreak = currentWinStreak;
      }

      netCoins = coinsWon - coinsLost;

      if (_pot > highestPotSeen) {
        highestPotSeen = _pot;
      }

      tx.set(matchesRef.doc(), {
        'gameType': 'Poker',
        'mode': 'singleplayer',
        'result': resultStr,
        'coinDelta': coinDelta,
        'startingCoins': persistedCoins,
        'endingCoins': newCoins,
        'finalChips': newCoins,
        'potAtEnd': _pot,
        'roomId': null,
        'opponentCount': 1,
        'winningHandName': null,
        'phaseEnded': _phase,
        'playedAt': FieldValue.serverTimestamp(),
      });

      tx.set(
          statsRef,
          {
            'gameType': 'Poker',
            'gamesPlayed': gamesPlayed,
            'wins': wins,
            'losses': losses,
            'coinsWon': coinsWon,
            'coinsLost': coinsLost,
            'netCoins': netCoins,
            'currentWinStreak': currentWinStreak,
            'bestWinStreak': bestWinStreak,
            'highestPotSeen': highestPotSeen,
            'singleplayerGames': singleplayerGames,
            'multiplayerGames': multiplayerGames,
            'singleplayerWins': singleplayerWins,
            'multiplayerWins': multiplayerWins,
            'lastPlayedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      tx.set(userRef, {
        'coins': newCoins,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _coins = newCoins;
        });
      }
    });
  }
//Moves Solo poker through pre flop, flop, turn, river, showdown
  Future<void> _advancePhase() async {
    if (!_roundActive || _roundOver) return;

    final deck = _freshDeck()
      ..removeWhere((c) =>
      _playerCards.contains(c) ||
          _opponentCards.contains(c) ||
          _communityCards.contains(c));

    if (_phase == 'preflop') {
      setState(() {
        _communityCards.addAll([
          deck.removeAt(0),
          deck.removeAt(0),
          deck.removeAt(0),
        ]);
        _phase = 'flop';
        _status = 'Flop dealt. Three community cards are now visible.';
      });
      return;
    }

    if (_phase == 'flop') {
      setState(() {
        _communityCards.add(deck.removeAt(0));
        _phase = 'turn';
        _status = 'Turn dealt. One more community card is visible.';
      });
      return;
    }

    if (_phase == 'turn') {
      setState(() {
        _communityCards.add(deck.removeAt(0));
        _phase = 'river';
        _status = 'River dealt. Final betting point.';
      });
      return;
    }

    await _showdown();
  }
//Calculates and saves solo poker winner
  Future<void> _showdown() async {
    final playerAll = [..._playerCards, ..._communityCards];
    final opponentAll = [..._opponentCards, ..._communityCards];

    final playerScore = _simpleScore(playerAll);
    final opponentScore = _simpleScore(opponentAll);

    final resultStr = playerScore >= opponentScore ? 'Win' : 'Loss';

    setState(() {
      _roundActive = false;
      _roundOver = true;
      _phase = 'showdown';
      _savingResult = true;
      _status = resultStr == 'Win'
          ? 'You win the pot at showdown.'
          : 'Opponent wins the pot.';
    });

    try {
      await _saveSingleplayerPokerResult(resultStr);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to save poker result: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingResult = false;
        });
      }
    }
  }
//Check action
  Future<void> _check() async {
    if (!_roundActive || _roundOver || _savingResult) return;
    setState(() {
      _status = 'You checked. No extra chips committed.';
    });
    await _advancePhase();
  }
//Raise action
  Future<void> _raise() async {
    if (!_roundActive || _roundOver || _savingResult) return;

    const raiseAmount = 50;

    if (_coins < (_playerBet + raiseAmount)) {
      setState(() {
        _status = 'Not enough coins to raise.';
      });
      return;
    }

    setState(() {
      _playerBet += raiseAmount;
      _opponentBet += raiseAmount;
      _pot += raiseAmount * 2;
      _status = 'You raised. Opponent called.';
    });

    await _advancePhase();
  }
//Fold action
  Future<void> _fold() async {
    if (!_roundActive || _roundOver || _savingResult) return;

    setState(() {
      _roundActive = false;
      _roundOver = true;
      _phase = 'folded';
      _savingResult = true;
      _status = 'You folded. Opponent wins the pot.';
    });

    try {
      await _saveSingleplayerPokerResult('Loss');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to save poker result: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingResult = false;
        });
      }
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

  String _resultLabel() {
    if (_phase == 'showdown') {
      final playerAll = [..._playerCards, ..._communityCards];
      final opponentAll = [..._opponentCards, ..._communityCards];
      final playerScore = _simpleScore(playerAll);
      final opponentScore = _simpleScore(opponentAll);
      return playerScore >= opponentScore ? 'WIN' : 'LOSS';
    }
    if (_phase == 'folded') return 'FOLDED';
    return _roundActive ? 'LIVE' : 'READY';
  }

  Color _resultColor() {
    if (_phase == 'showdown') {
      final playerAll = [..._playerCards, ..._communityCards];
      final opponentAll = [..._opponentCards, ..._communityCards];
      final playerScore = _simpleScore(playerAll);
      final opponentScore = _simpleScore(opponentAll);
      return playerScore >= opponentScore
          ? Colors.green.shade300
          : Colors.red.shade300;
    }
    if (_phase == 'folded') return Colors.red.shade300;
    return Colors.white70;
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

  Widget _opponentPanel() {
    return _panel(
      'Opponent',
      Column(
        children: [
          _cardRow(
            _roundOver ? _opponentCards : _opponentCards,
            emptyText: 'Opponent waiting',
            hidden: !_roundOver,
          ),
          const SizedBox(height: 10),
          Text(
            _roundOver
                ? 'Opponent hand revealed'
                : 'Opponent cards are hidden until the hand ends',
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
                : 'Both players use these cards to make the best possible hand.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: _pill(_phase.toUpperCase(), color: _phaseColor()),
    );
  }

  Widget _playerPanel() {
    return _panel(
      'Your Hole Cards',
      Column(
        children: [
          _cardRow(_playerCards),
          const SizedBox(height: 10),
          Text(
            'Your current bet: $_playerBet • Opponent bet: $_opponentBet',
            textAlign: TextAlign.center,
            style: const TextStyle(
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

  Widget _roundSummaryPanel() {
    if (!_roundOver) return const SizedBox.shrink();

    return _panel(
      'Round Result',
      Column(
        children: [
          Text(
            _resultLabel(),
            style: TextStyle(
              color: _resultColor(),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _phase == 'showdown'
                ? 'Pot: $_pot • Net result saved to your stats'
                : 'The hand ended before showdown',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: _pill(
        _savingResult ? 'SAVING' : 'DONE',
        color: _savingResult ? Colors.orange.shade300 : _resultColor(),
      ),
    );
  }

  Widget _buildActionButtons() {
    final actionLocked = _savingResult;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: actionLocked ? null : _check,
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
                onPressed: actionLocked ? null : _raise,
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
            onPressed: actionLocked ? null : _fold,
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
    final actionLocked = _savingResult;

    if (!_roundActive && !_roundOver) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: actionLocked ? null : _startRound,
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
          label: const Text('Start Round'),
        ),
      );
    }

    if (_roundActive) {
      return _buildActionButtons();
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: actionLocked ? null : _startRound,
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
        label: Text(_savingResult ? 'Saving...' : 'Play Again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roundStateText = _roundOver
        ? (_phase == 'folded' ? 'Hand ended by fold' : 'Hand complete')
        : (_roundActive ? 'Singleplayer hand active' : 'Ready to begin');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Singleplayer Poker'),
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
                  _pill('Mode: Singleplayer', color: Colors.blue.shade300),
                  _pill('Phase: ${_phase.toUpperCase()}', color: _phaseColor()),
                  _pill('Coins: $_coins'),
                  _pill('Pot: $_pot'),
                ],
              ),
              const SizedBox(height: 14),
              _statusBanner(),
              const SizedBox(height: 16),
              _tableSurface(
                child: Column(
                  children: [
                    _opponentPanel(),
                    const SizedBox(height: 14),
                    _communityPanel(),
                    const SizedBox(height: 14),
                    _playerPanel(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _panel(
                'Hand Flow',
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
                      'This solo mode is a simplified poker flow. You move through preflop, flop, turn, river, and showdown while your match history, coins, and stats are recorded.',
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_roundOver) ...[
                const SizedBox(height: 14),
                _roundSummaryPanel(),
              ],
              const SizedBox(height: 14),
              _buildBottomAction(),
            ],
          ),
        ),
      ),
    );
  }
}