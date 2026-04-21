import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SingleplayerPokerScreen extends StatefulWidget {
  const SingleplayerPokerScreen({super.key});

  @override
  State<SingleplayerPokerScreen> createState() => _SingleplayerPokerScreenState();
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
    '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'
  ];
  static const _suits = ['H', 'D', 'C', 'S'];

  @override
  void initState() {
    super.initState();
    _loadCoins();
  }

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
        bestWinStreak =
            ((existing['bestWinStreak'] ?? 0) as num).toInt();
        highestPotSeen =
            ((existing['highestPotSeen'] ?? 0) as num).toInt();
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


      final coinDelta =
      resultStr == 'Win' ? (_pot - _playerBet) : -_playerBet;

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

      tx.set(statsRef, {
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
      }, SetOptions(merge: true));

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

  Future<void> _check() async {
    if (!_roundActive || _roundOver || _savingResult) return;
    setState(() {
      _status = 'You checked. No extra chips committed.';
    });
    await _advancePhase();
  }

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
    final actionLocked = _savingResult;

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
                children: [
                  _chip('Mode: Singleplayer'),
                  _chip('Phase: ${_phase.toUpperCase()}'),
                  _chip('Coins: $_coins'),
                  _chip('Pot: $_pot'),
                ],
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
                  onPressed: actionLocked ? null : _startRound,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Round'),
                )
              else if (_roundActive)
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: actionLocked ? null : _check,
                            icon: const Icon(Icons.check),
                            label: const Text('Check'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: actionLocked ? null : _raise,
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
                        icon: const Icon(Icons.close),
                        label: const Text('Fold'),
                      ),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: actionLocked ? null : _startRound,
                  icon: const Icon(Icons.replay),
                  label: Text(_savingResult ? 'Saving...' : 'Play Again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}