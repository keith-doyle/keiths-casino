import 'dart:async';
import 'dart:convert';
import '../services/interstitial_ad_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import '../widgets/playing_card_widget.dart';

class BlackjackScreen extends StatefulWidget {
  final bool tutorialMode;

  const BlackjackScreen({
    super.key,
    this.tutorialMode = false,
  });

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

  bool _betLockedForHand = false;
  String? _resultStr;

  @override
  void initState() {
    super.initState();
    _loadCoins();
    _connectAndListen();
  }

  Future<void> _loadCoins() async {
    if (widget.tutorialMode) {
      if (!mounted) return;
      setState(() {
        _coins = 1000;
      });
      return;
    }

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

  void _applyTutorialResult(String resultStr) {
    final bet = _selectedBet;
    final coinDelta = resultStr == 'Win'
        ? bet
        : resultStr == 'Loss'
        ? -bet
        : 0;

    if (!mounted) return;
    setState(() {
      _coins += coinDelta;
      if (_coins < 0) _coins = 0;
    });
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

          final systemStatus = (msg["status"] ?? "").toString();

          setState(() {
            _status = systemStatus.toLowerCase().contains('connected to room')
                ? (widget.tutorialMode
                ? 'Deal a tutorial hand to begin.'
                : 'Deal a hand to begin.')
                : systemStatus;
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
            _resultStr = msg["result"]?.toString();
            _busy = false;
          });

          if (_gameOver && _betLockedForHand && !_savedThisHand) {
            _savedThisHand = true;
            try {
              if (widget.tutorialMode) {
                if (_resultStr != null) {
                  _applyTutorialResult(_resultStr!);
                }
              } else {
                await _saveMatchStatsAndCoins(_resultStr);
                await InterstitialAdService.handleCompletedGame();
              }
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
    if (!mounted) return;

    setState(() => _busy = true);

    if (action == "deal") {
      _savedThisHand = false;
      _gameId = null;
      _betLockedForHand = false;
      _resultStr = null;
      _gameOver = false;
      _dealerRevealed = false;
      _playerCards = [];
      _dealerCards = [];
      _playerTotal = 0;
      _dealerTotal = 0;
      _status = widget.tutorialMode
          ? 'Dealing a new tutorial hand...'
          : 'Dealing a new hand...';
    }

    _ws.sendJson({
      "type": "action",
      "action": action,
      "game_id": _gameId,
    });
  }

  Future<void> _confirmBetForHand() async {
    if (_selectedBet > _coins) {
      setState(() {
        _status = "Not enough coins for that bet.";
      });
      return;
    }

    setState(() {
      _betLockedForHand = true;
      _status = widget.tutorialMode
          ? "Practice bet locked. Play your hand."
          : (_gameOver
          ? "Bet locked. Saving result..."
          : "Bet locked. Play your hand.");
    });

    if (_gameOver && !_savedThisHand) {
      _savedThisHand = true;
      try {
        if (widget.tutorialMode) {
          if (_resultStr != null) {
            _applyTutorialResult(_resultStr!);
          }
        } else {
          await _saveMatchStatsAndCoins(_resultStr);
          await InterstitialAdService.handleCompletedGame();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _status = "Match/stat/coin save failed: $e";
        });
      }
    }
  }

  Future<void> _saveMatchStatsAndCoins(dynamic result) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not signed in");

    final resultStr = (result is String) ? result : null;
    if (resultStr == null) {
      throw Exception("Missing result from backend payload");
    }

    if (resultStr != 'Win' && resultStr != 'Loss' && resultStr != 'Push') {
      throw Exception('Invalid result value: $resultStr');
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final matchesRef = userRef.collection('matches');
    final statsRef = userRef.collection('stats').doc('blackjack');

    final bet = _selectedBet;
    final coinDelta = resultStr == 'Win'
        ? bet
        : resultStr == 'Loss'
        ? -bet
        : 0;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final statsSnap = await tx.get(statsRef);

      int gamesPlayed = 0;
      int wins = 0;
      int losses = 0;
      int pushes = 0;

      int singleplayerGames = 0;
      int multiplayerGames = 0;
      int singleplayerWins = 0;
      int multiplayerWins = 0;

      int coinsWon = 0;
      int coinsLost = 0;
      int netCoins = 0;
      int highestBet = 0;
      int biggestWin = 0;

      int currentWinStreak = 0;
      int bestWinStreak = 0;

      int coins = 0;
      bool legacyStats = false;

      if (statsSnap.exists) {
        final existing = statsSnap.data() as Map<String, dynamic>;
        gamesPlayed = ((existing['gamesPlayed'] ?? 0) as num).toInt();
        wins = ((existing['wins'] ?? 0) as num).toInt();
        losses = ((existing['losses'] ?? 0) as num).toInt();
        pushes = ((existing['pushes'] ?? 0) as num).toInt();

        legacyStats = !existing.containsKey('singleplayerGames') ||
            !existing.containsKey('multiplayerGames');

        if (!legacyStats) {
          singleplayerGames =
              ((existing['singleplayerGames'] ?? 0) as num).toInt();
          multiplayerGames =
              ((existing['multiplayerGames'] ?? 0) as num).toInt();
          singleplayerWins =
              ((existing['singleplayerWins'] ?? 0) as num).toInt();
          multiplayerWins =
              ((existing['multiplayerWins'] ?? 0) as num).toInt();
          coinsWon = ((existing['coinsWon'] ?? 0) as num).toInt();
          coinsLost = ((existing['coinsLost'] ?? 0) as num).toInt();
          netCoins = ((existing['netCoins'] ?? 0) as num).toInt();
          highestBet = ((existing['highestBet'] ?? 0) as num).toInt();
          biggestWin = ((existing['biggestWin'] ?? 0) as num).toInt();
          currentWinStreak =
              ((existing['currentWinStreak'] ?? 0) as num).toInt();
          bestWinStreak =
              ((existing['bestWinStreak'] ?? 0) as num).toInt();
        } else {
          singleplayerGames = gamesPlayed;
          multiplayerGames = 0;
          singleplayerWins = wins;
          multiplayerWins = 0;
        }
      }

      if (userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>;
        coins = ((userData['coins'] ?? 0) as num).toInt();
      }

      gamesPlayed += 1;
      singleplayerGames += 1;

      if (resultStr == 'Win') {
        wins += 1;
        singleplayerWins += 1;
        coinsWon += bet;
        currentWinStreak += 1;
        if (bet > biggestWin) biggestWin = bet;
      } else if (resultStr == 'Loss') {
        losses += 1;
        coinsLost += bet;
        currentWinStreak = 0;
      } else {
        pushes += 1;
        currentWinStreak = 0;
      }

      if (currentWinStreak > bestWinStreak) {
        bestWinStreak = currentWinStreak;
      }

      if (bet > highestBet) {
        highestBet = bet;
      }

      netCoins = coinsWon - coinsLost;

      coins += coinDelta;
      if (coins < 0) coins = 0;

      final matchDoc = matchesRef.doc();
      tx.set(matchDoc, {
        'gameType': 'Blackjack',
        'mode': 'singleplayer',
        'result': resultStr,
        'bet': bet,
        'coinDelta': coinDelta,
        'playerTotal': _playerTotal,
        'dealerTotal': _dealerTotal,
        'roomId': null,
        'opponentCount': 0,
        'playedAt': FieldValue.serverTimestamp(),
      });

      tx.set(statsRef, {
        'gameType': 'Blackjack',
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'losses': losses,
        'pushes': pushes,
        'singleplayerGames': singleplayerGames,
        'multiplayerGames': multiplayerGames,
        'singleplayerWins': singleplayerWins,
        'multiplayerWins': multiplayerWins,
        'coinsWon': coinsWon,
        'coinsLost': coinsLost,
        'netCoins': netCoins,
        'highestBet': highestBet,
        'biggestWin': biggestWin,
        'currentWinStreak': currentWinStreak,
        'bestWinStreak': bestWinStreak,
        'lastPlayedAt': FieldValue.serverTimestamp(),
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

  int? _dealerUpCardValue() {
    if (_dealerCards.isEmpty) return null;
    final id = _dealerCards.first.toUpperCase();
    if (id.length < 2) return null;

    final rank = id.substring(0, id.length - 1);

    switch (rank) {
      case 'A':
        return 11;
      case 'K':
      case 'Q':
      case 'J':
      case '10':
        return 10;
      default:
        return int.tryParse(rank);
    }
  }

  String _tutorialHeading() {
    if (_gameId == null) return 'How tutorial mode works';
    if (_gameOver) return 'Hand review';
    if (!_betLockedForHand) return 'Step 1: lock in your practice bet';
    return 'Live decision hint';
  }

  String _tutorialBody() {
    if (_gameId == null) {
      return 'Deal a hand first. Once your cards appear, choose a practice bet, confirm it, and then decide whether to hit or stand.';
    }

    if (!_betLockedForHand) {
      return 'Choose your practice bet now. After confirming, you will play the hand and the tutorial will explain your decision points.';
    }

    if (_gameOver) {
      if (_resultStr == 'Win') {
        return 'You won the hand. Compare your final total against the dealer total and note how avoiding a bust helped you finish ahead.';
      }
      if (_resultStr == 'Loss') {
        return 'You lost the hand. Check whether you busted or whether the dealer finished with a stronger total.';
      }
      return 'A push means the hand tied. Neither side won or lost the bet.';
    }

    final dealerUp = _dealerUpCardValue();
    final total = _playerTotal;

    if (total <= 11) {
      return 'Your total is $total. Hitting is very safe because one extra card cannot bust you.';
    }

    if (total >= 17) {
      return 'Your total is $total. Standing is usually the safer choice because another card often risks a bust.';
    }

    if (total >= 12 && total <= 16) {
      if (dealerUp != null && dealerUp >= 7) {
        return 'You have $total and the dealer shows $dealerUp. The dealer is showing strength, so hitting is often the better choice.';
      }
      if (dealerUp != null && dealerUp <= 6) {
        return 'You have $total and the dealer shows $dealerUp. The dealer is weaker here, so standing is often more reasonable.';
      }
    }

    return 'Compare your total with the dealer’s visible up-card. Strong totals tend to stand. Weak or medium totals often need another card.';
  }

  String _tutorialTip() {
    if (_gameId == null) {
      return 'Rule reminder: go over 21 and you bust immediately.';
    }
    if (_gameOver) {
      return 'Rule reminder: after your turn ends, the dealer reveals the hidden card and completes the hand.';
    }
    if (!_betLockedForHand) {
      return 'Rule reminder: face cards count as 10. Aces can count as 1 or 11.';
    }
    return 'Rule reminder: blackjack decisions are about card totals and dealer pressure, not just guessing.';
  }

  Color _resultColor(String? result) {
    switch (result) {
      case 'Win':
        return Colors.green.shade300;
      case 'Loss':
        return Colors.red.shade300;
      case 'Push':
        return Colors.orange.shade300;
      default:
        return Colors.white;
    }
  }

  String _heroStatusText() {
    if (_gameId == null) {
      return widget.tutorialMode
          ? 'Deal a tutorial hand to begin'
          : 'Deal a hand to begin';
    }

    if (_gameOver) {
      if (_resultStr == 'Win') return 'You won this hand';
      if (_resultStr == 'Loss') return 'Dealer won this hand';
      if (_resultStr == 'Push') return 'Hand ended in a push';
      return 'Hand complete';
    }

    if (!_betLockedForHand) {
      return widget.tutorialMode
          ? 'Choose and confirm your practice bet'
          : 'Choose and confirm your bet';
    }

    return 'Your move';
  }

  Widget _pill(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: (color ?? Colors.black).withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _badge(
      String label, {
        required Color fg,
        required Color bg,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildFanHand(
      List<String> cards, {
        required double cardWidth,
        required double cardHeight,
        required double overlap,
        bool hideDealerSecond = false,
      }) {
    if (cards.isEmpty) {
      return SizedBox(
        height: cardHeight,
        child: const Center(
          child: Text(
            'No cards yet',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    final visibleWidth = cardWidth + ((cards.length - 1) * overlap);

    return SizedBox(
      width: visibleWidth,
      height: cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(cards.length, (i) {
          return Positioned(
            left: i * overlap,
            child: PlayingCardWidget(
              cardId: cards[i],
              faceDown: hideDealerSecond && i == 1,
              width: cardWidth,
              height: cardHeight,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _pill(
                widget.tutorialMode ? 'TUTORIAL BLACKJACK' : 'SINGLEPLAYER BLACKJACK',
                color: widget.tutorialMode
                    ? Colors.amber.shade200
                    : Colors.white,
              ),
              _pill('Bet ${_selectedBet}'),
              _pill(widget.tutorialMode ? 'Practice Coins $_coins' : 'Coins $_coins'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _heroStatusText(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gameOver ? _resultColor(_resultStr) : Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.tutorialMode
                ? 'Tutorial hands use practice coins only and do not affect your saved profile stats.'
                : 'Singleplayer hands save coins, match history, and blackjack stats automatically.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealerSeat() {
    final dealerTotalText = _dealerRevealed ? _dealerTotal.toString() : '??';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          const Text(
            'Dealer',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildFanHand(
              _dealerCards,
              cardWidth: 64,
              cardHeight: 96,
              overlap: 38,
              hideDealerSecond: !_dealerRevealed && _dealerCards.length >= 2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Dealer total: $dealerTotalText',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoLine({
    required int bet,
    required int total,
    required String? result,
  }) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        Text(
          'Bet: $bet',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        Text(
          'Total: $total',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        Text(
          'Result: ${result ?? "-"}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: result == null ? Colors.white70 : _resultColor(result),
          ),
        ),
      ],
    );
  }

  Widget _buildMySeat() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _betLockedForHand
              ? Colors.green.withOpacity(0.45)
              : Colors.white24,
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'You',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              _badge(
                widget.tutorialMode ? 'TUTORIAL' : 'SOLO',
                fg: widget.tutorialMode
                    ? Colors.amber.shade100
                    : Colors.blue.shade100,
                bg: widget.tutorialMode
                    ? Colors.amber.withOpacity(0.25)
                    : Colors.blue.withOpacity(0.25),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                widget.tutorialMode
                    ? 'Practice Coins: $_coins'
                    : 'Coins: $_coins',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'Bet: $_selectedBet',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildFanHand(
              _playerCards,
              cardWidth: 64,
              cardHeight: 96,
              overlap: 30,
            ),
          ),
          const SizedBox(height: 10),
          _buildCompactInfoLine(
            bet: _selectedBet,
            total: _playerTotal,
            result: _resultStr,
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialCard() {
    if (!widget.tutorialMode) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tutorialHeading(),
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tutorialBody(),
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tutorialTip(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetSelector() {
    Widget chip(int amount) {
      final selected = _selectedBet == amount;

      return ChoiceChip(
        label: Text('$amount'),
        selected: selected,
        onSelected: _busy || _betLockedForHand
            ? null
            : (_) {
          setState(() {
            _selectedBet = amount;
          });
        },
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.tutorialMode
                      ? 'Choose your practice bet'
                      : 'Choose your bet',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                _betLockedForHand ? 'Locked' : 'Select',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.tutorialMode
                  ? 'This only affects practice coins in tutorial mode.'
                  : 'This hand will use your saved balance and stats.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              chip(10),
              chip(25),
              chip(50),
              chip(100),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        _status,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildRoundSummary() {
    if (!_gameOver) return const SizedBox.shrink();

    final result = _resultStr ?? '-';
    final coinDelta = result == 'Win'
        ? _selectedBet
        : result == 'Loss'
        ? -_selectedBet
        : 0;

    final coinText = coinDelta > 0
        ? '+$coinDelta'
        : coinDelta < 0
        ? '$coinDelta'
        : '0';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _resultColor(result).withOpacity(0.8),
        ),
      ),
      child: Column(
        children: [
          Text(
            result.toUpperCase(),
            style: TextStyle(
              color: _resultColor(result),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.tutorialMode
                ? 'Practice result: $coinText'
                : 'Coin change: $coinText',
            style: TextStyle(
              color: _resultColor(result),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                'Your total: $_playerTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Dealer total: $_dealerTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Bet: $_selectedBet',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final canPlayMove =
        !_busy && !_gameOver && _gameId != null && _betLockedForHand;
    final canDeal = !_busy && (_gameId == null || _gameOver);
    final canConfirmBet = !_busy && _gameId != null && !_betLockedForHand;

    ButtonStyle style(Color bg) {
      return FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    if (_gameOver || _gameId == null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: style(const Color(0xFF3B82F6)),
          onPressed: canDeal ? () => _sendAction("deal") : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(_busy ? 'Working...' : 'Deal Hand'),
        ),
      );
    }

    if (!_betLockedForHand) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: style(const Color(0xFF0F766E)),
          onPressed: canConfirmBet ? _confirmBetForHand : null,
          icon: const Icon(Icons.payments),
          label: Text(
            widget.tutorialMode ? 'Confirm Practice Bet' : 'Confirm Bet',
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: style(const Color(0xFFEF4444)),
            onPressed: canPlayMove ? () => _sendAction("hit") : null,
            icon: const Icon(Icons.add),
            label: const Text('Hit'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: style(const Color(0xFF2563EB)),
            onPressed: canPlayMove ? () => _sendAction("stand") : null,
            icon: const Icon(Icons.pan_tool_alt_outlined),
            label: const Text('Stand'),
          ),
        ),
      ],
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tutorialMode ? 'Blackjack Tutorial' : 'Blackjack'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF14532D),
              Color(0xFF166534),
              Color(0xFF14532D),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 14 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 14),
                if (widget.tutorialMode) ...[
                  _buildTutorialCard(),
                  const SizedBox(height: 14),
                ],
                _buildDealerSeat(),
                const SizedBox(height: 16),
                _buildMySeat(),
                const SizedBox(height: 12),
                if (_gameId != null && !_gameOver) ...[
                  _buildBetSelector(),
                  const SizedBox(height: 12),
                ],
                if (_gameOver) ...[
                  _buildRoundSummary(),
                  const SizedBox(height: 12),
                ],
                _buildStatusBar(),
                const SizedBox(height: 12),
                _buildControls(),
                if (_gameId == null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      widget.tutorialMode
                          ? 'Tutorial flow:\n1. Deal cards\n2. Choose a practice bet\n3. Confirm it\n4. Read the hint\n5. Decide whether to hit or stand'
                          : 'Flow:\n1. Deal cards\n2. Choose your bet\n3. Confirm it\n4. Play hit or stand\n5. Result saves automatically',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}