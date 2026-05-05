import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import '../widgets/playing_card_widget.dart';

class PokerTableScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;

  const PokerTableScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<PokerTableScreen> createState() => _PokerTableScreenState();
}

class _PokerTableScreenState extends State<PokerTableScreen> {
  final BlackjackWsService _ws = BlackjackWsService();
  StreamSubscription? _sub;

  List<Map<String, dynamic>> _players = [];
  List<String> _communityCards = [];
  String _status = 'Connecting...';
  String? _hostPlayerId;
  String? _turnPlayerId;
  bool _busy = true;
  bool _gameStarted = false;
  bool _roundOver = false;
  bool _savedThisRound = false;

  String _phase = 'waiting';
  int _pot = 0;
  int _currentBet = 0;
  String? _winnerPlayerId;
  String? _winningHandName;

  String? _dealerPlayerId;
  String? _smallBlindPlayerId;
  String? _bigBlindPlayerId;
  int _smallBlindAmount = 0;
  int _bigBlindAmount = 0;

  int _coins = 0;

  @override
  void initState() {
    super.initState();
    _loadCoins().then((_) {
      _connectAndListen();
    });
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
//Connects to websocket, flutter receives table_state for poker
  void _connectAndListen() {
    _ws.connectToPokerTable(roomId: widget.roomId);

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
          _ws.sendJson({
            "type": "join",
            "player_id": widget.playerId,
            "player_name": widget.playerName,
            "coins": _coins,
          });

          if (!mounted) return;
          setState(() {
            _status = (msg["status"] ?? "").toString();
            _busy = false;
          });
          return;
        }

        if (type == "error") {
          if (!mounted) return;
          final errorText = (msg["status"] ?? "Unknown error").toString();
          setState(() {
            _status = errorText;
            _busy = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorText)),
          );
          return;
        }
        //Flutter table state, reads community cards, phase,pot,bet,winner,blinds from payload
        if (type == "table_state") {
          final previousRoundOver = _roundOver;

          if (!mounted) return;
          setState(() {
            _players = List<Map<String, dynamic>>.from(msg["players"] ?? []);
            _communityCards = List<String>.from(msg["community_cards"] ?? []);
            _hostPlayerId = msg["host_player_id"]?.toString();
            _turnPlayerId = msg["turn_player_id"]?.toString();
            _status = (msg["status"] ?? "Connected").toString();
            _gameStarted = (msg["game_started"] ?? false) as bool;
            _roundOver = (msg["round_over"] ?? false) as bool;
            _phase = (msg["phase"] ?? "waiting").toString();
            _pot = ((msg["pot"] ?? 0) as num).toInt();
            _currentBet = ((msg["current_bet"] ?? 0) as num).toInt();
            _winnerPlayerId = msg["winner_player_id"]?.toString();
            _winningHandName = msg["winning_hand_name"]?.toString();

            _dealerPlayerId = msg["dealer_player_id"]?.toString();
            _smallBlindPlayerId = msg["small_blind_player_id"]?.toString();
            _bigBlindPlayerId = msg["big_blind_player_id"]?.toString();
            _smallBlindAmount =
                ((msg["small_blind_amount"] ?? 0) as num).toInt();
            _bigBlindAmount = ((msg["big_blind_amount"] ?? 0) as num).toInt();

            _busy = false;
          });

          if (!_roundOver) {
            _savedThisRound = false;
          }
          //save result and record stats and coins, prevents duplicate saves from repeated final table states
          if (!previousRoundOver && _roundOver && !_savedThisRound) {
            final me = _myPlayer;
            if (me != null) {
              _savedThisRound = true;
              try {
                await _savePokerMatchStatsAndCoins();
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _status = "Poker match/stat save failed: $e";
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
          _status = "Connection error: $e";
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connection error: $e")),
        );
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
//Getters from backends payload table_state
  bool get _isHost => _hostPlayerId == widget.playerId;
  bool get _isMyTurn => _turnPlayerId == widget.playerId;
  bool get _iWon => _winnerPlayerId == widget.playerId;

  Map<String, dynamic>? get _myPlayer {
    try {
      return _players.firstWhere((p) => p["id"] == widget.playerId);
    } catch (_) {
      return null;
    }
  }

  List<String> get _myCards => List<String>.from(_myPlayer?["cards"] ?? []);
  int get _myChips => ((_myPlayer?["chips"] ?? 0) as num).toInt();
  int get _myCurrentBet => ((_myPlayer?["current_bet"] ?? 0) as num).toInt();
//Persists Poker multiplayer result and balance
  Future<void> _savePokerMatchStatsAndCoins() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not signed in");

    final me = _myPlayer;
    if (me == null) throw Exception("Player state missing");

    final resultStr = _iWon ? 'Win' : 'Loss';
    final finalChips = _myChips;
    final coinDelta = finalChips - _coins;

    final rawOpponentCount =
        _players.where((p) => p["id"] != widget.playerId).length;
    final opponentCount = rawOpponentCount < 1 ? 1 : rawOpponentCount;
//User ref collection matches and stats
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final matchesRef = userRef.collection('matches');
    final statsRef = userRef.collection('stats').doc('poker');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final statsSnap = await tx.get(statsRef);

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

      int persistedCoins = _coins;
      if (userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>;
        persistedCoins = ((userData['coins'] ?? _coins) as num).toInt();
      }

      gamesPlayed += 1;
      multiplayerGames += 1;

      if (resultStr == 'Win') {
        wins += 1;
        multiplayerWins += 1;
        currentWinStreak += 1;
      } else {
        losses += 1;
        currentWinStreak = 0;
      }

      if (currentWinStreak > bestWinStreak) {
        bestWinStreak = currentWinStreak;
      }

      if (coinDelta > 0) {
        coinsWon += coinDelta;
      } else if (coinDelta < 0) {
        coinsLost += coinDelta.abs();
      }

      netCoins = coinsWon - coinsLost;

      if (_pot > highestPotSeen) {
        highestPotSeen = _pot;
      }

      final newCoins = finalChips < 0 ? 0 : finalChips;

      final matchDoc = matchesRef.doc();
      tx.set(matchDoc, {
        'gameType': 'Poker',
        'mode': 'multiplayer',
        'result': resultStr,
        'coinDelta': coinDelta,
        'startingCoins': persistedCoins,
        'endingCoins': newCoins,
        'finalChips': finalChips,
        'potAtEnd': _pot,
        'roomId': widget.roomId,
        'opponentCount': opponentCount,
        'winningHandName': _winningHandName,
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
        SetOptions(merge: true),
      );

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
//Send fold, check, call, raise intent to backend. JSON type == action sent to backend
  void _sendAction(String action, {int amount = 0}) {
    if (_busy || !_isMyTurn || _roundOver || !_gameStarted) return;

    setState(() => _busy = true);

    _ws.sendJson({
      "type": "action",
      "action": action,
      "amount": amount,
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _busy = false);
      }
    });
  }
//Builds text for waiting, host start, own turn, or another player's turn
  String _turnLabel() {
    if (_roundOver) return 'Round complete';
    if (!_gameStarted) {
      return _players.length < 2
          ? 'Waiting for more players'
          : (_isHost ? 'You can start the round' : 'Waiting for host to start');
    }
    if (_turnPlayerId == null) return 'No active turn';

    try {
      final player = _players.firstWhere((p) => p["id"] == _turnPlayerId);
      final name = (player["name"] ?? 'Player').toString();
      return _isMyTurn ? 'Your turn - act now' : 'Waiting for $name';
    } catch (_) {
      return 'Turn active';
    }
  }
//Converts backend phase values into ui wording
  String _buildStatusText() {
    if (_roundOver) return _winnerLabel();

    switch (_phase) {
      case 'preflop':
        return 'Preflop betting';
      case 'flop':
        return 'Flop betting';
      case 'turn':
        return 'Turn betting';
      case 'river':
        return 'River betting';
      default:
        if (!_gameStarted) {
          return _players.length < 2
              ? 'Waiting for players to join the table'
              : 'Ready to start the round';
        }
        return _status;
    }
  }
//Shows the resolved backend winner in english
  String _winnerLabel() {
    if (_iWon) {
      return _winningHandName == null
          ? 'You won the round'
          : 'You won with $_winningHandName';
    }

    try {
      final winner = _players.firstWhere((p) => p["id"] == _winnerPlayerId);
      final name = (winner["name"] ?? 'Player').toString();
      return _winningHandName == null
          ? '$name won the round'
          : '$name won with $_winningHandName';
    } catch (_) {
      return 'Round complete';
    }
  }
//Color coding for phases
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
      default:
        return Colors.white70;
    }
  }
//reusable small status pill for phase, pot,bet and player data
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
//displays role badges such as dealer big blind small blind
  Widget _roleBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: color,
          fontSize: 11,
        ),
      ),
    );
  }
//reusable titled container for table subsections
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
//Creates the darker green poker table style
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
            const Color(0xFF1E293B),
            const Color(0xFF0F172A),
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
//renders a compact row playingcardwidgets or face down/placeholder cards
  Widget _buildSmallCards(List<String> cards) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: cards
            .map(
              (c) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: PlayingCardWidget(
              cardId: c,
              width: 44,
              height: 64,
            ),
          ),
        )
            .toList(),
      ),
    );
  }
//Shows the five card board area filling missing cards with placeholders until dealt
  Widget _buildCommunityCards() {
    if (_communityCards.isEmpty) {
      return const Text(
        'No community cards yet',
        style: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _communityCards
            .map(
              (c) => Padding(
            padding: const EdgeInsets.all(4),
            child: PlayingCardWidget(
              cardId: c,
              width: 58,
              height: 86,
            ),
          ),
        )
            .toList(),
      ),
    );
  }
//Shows the current players hole cards + chip bet info
  Widget _buildMyCards() {
    if (_myCards.isEmpty) {
      return const Text(
        'No hole cards yet',
        style: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _myCards
            .map(
              (c) => Padding(
            padding: const EdgeInsets.all(4),
            child: PlayingCardWidget(
              cardId: c,
              width: 58,
              height: 86,
            ),
          ),
        )
            .toList(),
      ),
    );
  }
//Build a player card for each seat with name chips bet folded state role badges and revealed cards at showdown
  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final id = player["id"];
    final isTurn = id == _turnPlayerId;
    final isDealer = id == _dealerPlayerId;
    final isSmallBlind = id == _smallBlindPlayerId;
    final isBigBlind = id == _bigBlindPlayerId;
    final isWinner = id == _winnerPlayerId;
    final isYou = id == widget.playerId;
    final folded = (player["folded"] ?? false) as bool;
    final handName = (player["hand_name"] ?? '').toString();
    final chips = ((player["chips"] ?? 0) as num).toInt();
    final currentBet = ((player["current_bet"] ?? 0) as num).toInt();
    final cards = List<String>.from(player["cards"] ?? []);

    String subtitle = 'Chips: $chips • Bet: $currentBet';
    if (folded) {
      subtitle = 'Folded • Chips: $chips • Bet: $currentBet';
    } else if (_roundOver && handName.isNotEmpty) {
      subtitle = '$handName • Chips: $chips';
    } else if (isTurn) {
      subtitle = 'Act now • Chips: $chips • Bet: $currentBet';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTurn
            ? Colors.green.withOpacity(0.14)
            : isWinner
            ? Colors.green.withOpacity(0.10)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTurn
              ? Colors.green.shade300.withOpacity(0.75)
              : isWinner
              ? Colors.green.withOpacity(0.35)
              : Colors.white12,
          width: isTurn ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (player["name"] ?? 'Player').toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isDealer) _roleBadge('D', Colors.orange),
                  if (isSmallBlind) _roleBadge('SB', Colors.blue),
                  if (isBigBlind) _roleBadge('BB', Colors.red),
                  if (isWinner) _roleBadge('WIN', Colors.green),
                  if (isYou) _roleBadge('YOU', Colors.deepPurple.shade200),
                  if (isTurn) _roleBadge('TURN', Colors.green.shade300),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_roundOver && cards.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildSmallCards(cards),
            ),
          ],
        ],
      ),
    );
  }
//Buttons are enabled according to current betting state
  Widget _buildPrimaryActionArea() {
    ButtonStyle style(Color bg) {
      return FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      );
    }

    if (_roundOver) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy || !_isHost || _players.length < 2
              ? null
              : () {
            setState(() => _busy = true);
            _ws.sendStart();
          },
          style: style(const Color(0xFF3B82F6)),
          icon: const Icon(Icons.replay),
          label: Text(
            _isHost ? 'Start New Round' : 'Waiting for host',
          ),
        ),
      );
    }

    if (!_gameStarted) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy || !_isHost || _players.length < 2
              ? null
              : () {
            setState(() => _busy = true);
            _ws.sendStart();
          },
          style: style(const Color(0xFF3B82F6)),
          icon: const Icon(Icons.play_arrow),
          label: Text(
            _players.length < 2
                ? 'Need 2 players to start'
                : (_isHost ? 'Start Round' : 'Waiting for host'),
          ),
        ),
      );
    }

    if (!_isMyTurn) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: null,
          style: style(const Color(0xFF334155)),
          icon: const Icon(Icons.hourglass_bottom),
          label: Text(_turnLabel()),
        ),
      );
    }

    final toCall = _currentBet - _myCurrentBet;
    final canCheck = toCall == 0;
    final canCall = toCall > 0 && _myChips > 0;
    final raiseAmount = _currentBet + 50;
    final canRaise = _myChips >= (raiseAmount - _myCurrentBet);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !canCheck ? null : () => _sendAction('check'),
                style: style(const Color(0xFF2563EB)),
                icon: const Icon(Icons.check),
                label: const Text('Check'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !canCall ? null : () => _sendAction('call'),
                style: style(const Color(0xFF0F766E)),
                icon: const Icon(Icons.call_made),
                label: Text(canCall ? 'Call $toCall' : 'Call'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _sendAction('fold'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: Colors.red.shade200,
                  side: BorderSide(
                    color: Colors.red.shade200.withOpacity(0.55),
                  ),
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
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !canRaise
                    ? null
                    : () => _sendAction('raise', amount: raiseAmount),
                style: style(const Color(0xFF7C3AED)),
                icon: const Icon(Icons.arrow_upward),
                label: Text('Raise to $raiseAmount'),
              ),
            ),
          ],
        ),
      ],
    );
  }
//cancels websocket stream and disconnects service
  @override
  void dispose() {
    _sub?.cancel();
    _ws.disconnect();
    super.dispose();
  }
//Composes full poker table screen, header phase/pot info community cards etc
  @override
  Widget build(BuildContext context) {
    final tableStateText = _roundOver
        ? 'Round complete'
        : _gameStarted
        ? 'Multiplayer hand active'
        : 'Waiting to start';

    return Scaffold(
      appBar: AppBar(
        title: Text('Poker Table (${widget.roomId})'),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _pill('Room ${widget.roomId}'),
                          _pill('Players ${_players.length}'),
                          _pill(
                            'Blinds $_smallBlindAmount / $_bigBlindAmount',
                            color: Colors.orange.shade300,
                          ),
                          _pill(
                            'Phase ${_phase.toUpperCase()}',
                            color: _phaseColor(),
                          ),
                          _pill('Coins $_coins'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _buildStatusText(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _turnLabel(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isMyTurn
                                ? Colors.green.shade300
                                : Colors.white70,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_roundOver && _winnerPlayerId != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.45),
                            ),
                          ),
                          child: Text(
                            _winnerLabel(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _tableSurface(
                        child: Column(
                          children: [
                            _panel(
                              'Community Cards',
                              Column(
                                children: [
                                  _buildCommunityCards(),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Pot: $_pot',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Current bet: $_currentBet',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: _pill(
                                tableStateText.toUpperCase(),
                                color: _roundOver
                                    ? Colors.orange.shade300
                                    : _phaseColor(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _panel(
                              'Your Hole Cards',
                              Column(
                                children: [
                                  _buildMyCards(),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Your table chips: $_myChips • Your bet: $_myCurrentBet',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: _pill(
                                _isMyTurn ? 'YOUR TURN' : 'YOU',
                                color: _isMyTurn
                                    ? Colors.green.shade300
                                    : Colors.blue.shade300,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_players.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              _busy
                                  ? 'Joining poker table...'
                                  : 'No players connected',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        _panel(
                          'Players',
                          Column(
                            children: _players
                                .map((player) => _buildPlayerCard(player))
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 14),
                      _buildPrimaryActionArea(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}