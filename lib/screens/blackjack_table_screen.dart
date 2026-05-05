import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import '../widgets/playing_card_widget.dart';

class BlackjackTableScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;

  const BlackjackTableScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<BlackjackTableScreen> createState() => _BlackjackTableScreenState();
}

class _BlackjackTableScreenState extends State<BlackjackTableScreen> {
  final BlackjackWsService _ws = BlackjackWsService();
  StreamSubscription? _sub;

  List<String> _dealerCards = [];
  int? _dealerTotal;
  List<Map<String, dynamic>> _players = [];

  String _status = 'Connecting...';
  String? _hostPlayerId;
  String? _turnPlayerId;
  String _phase = 'waiting';

  bool _gameStarted = false;
  bool _gameOver = false;
  bool _dealerRevealed = false;
  bool _bettingOpen = false;
  bool _busy = true;
  bool _savedThisRound = false;

  int _coins = 0;
  int _selectedBet = 10;

  @override
  void initState() {
    super.initState();
    _loadCoins();
    _connectAndListen();
  }
//Loads players balance for multiplayer betting
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
//Connects to websocket, flutter receives table_state for blackjack
  void _connectAndListen() {
    _ws.connectToBlackjackTable(roomId: widget.roomId);

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
          _ws.join(
            playerId: widget.playerId,
            playerName: widget.playerName,
          );

          if (!mounted) return;

          final systemStatus = (msg["status"] ?? "").toString();

          setState(() {
            _status = systemStatus.toLowerCase().contains('connected to room')
                ? 'Waiting for table update.'
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

        if (type == "table_state") {
          final previousGameOver = _gameOver;
          final players = List<Map<String, dynamic>>.from(msg["players"] ?? []);

          if (!mounted) return;
          setState(() {
            _dealerCards = List<String>.from(msg["dealer_cards"] ?? []);
            _dealerTotal = msg["dealer_total"] as int?;
            _players = players;

            _status = (msg["status"] ?? "").toString();
            _hostPlayerId = msg["host_player_id"]?.toString();
            _turnPlayerId = msg["turn_player_id"]?.toString();
            _phase = (msg["phase"] ?? "waiting").toString();

            _gameStarted = (msg["game_started"] ?? false) as bool;
            _gameOver = (msg["game_over"] ?? false) as bool;
            _dealerRevealed = (msg["dealer_revealed"] ?? false) as bool;
            _bettingOpen = (msg["betting_open"] ?? false) as bool;

            final myBetFromState = players
                .where((p) => p["id"] == widget.playerId)
                .map((p) => ((p["bet"] ?? 0) as num).toInt())
                .cast<int?>()
                .firstWhere((_) => true, orElse: () => null);

            if (myBetFromState != null && myBetFromState > 0) {
              _selectedBet = myBetFromState;
            }

            _busy = false;
          });

          if (!_gameOver) {
            _savedThisRound = false;
          }
          //save result and record stats and coins, prevents duplicate saves from repeated final table states
          if (!previousGameOver && _gameOver && !_savedThisRound) {
            final me = _myPlayer;
            final result = me?["result"]?.toString();

            if (result == "Win" || result == "Loss" || result == "Push") {
              _savedThisRound = true;
              try {
                await _saveMatchStatsAndCoins(result!);
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _status = "Match/stat/coin save failed: $e";
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
//These getters convert backend JSON into ui permissions
  Map<String, dynamic>? get _myPlayer {
    try {
      return _players.firstWhere((p) => p["id"] == widget.playerId);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> get _opponents =>
      _players.where((p) => p["id"] != widget.playerId).take(2).toList();

  bool get _isHost => _hostPlayerId == widget.playerId;
  bool get _isMyTurn => _turnPlayerId == widget.playerId;
  bool get _joinedMidRound =>
      ((_myPlayer?["joined_mid_round"] ?? false) as bool);

  int get _myBet => ((_myPlayer?["bet"] ?? 0) as num).toInt();

  bool get _canStartRound =>
      !_busy && !_gameStarted && _players.length >= 2 && _isHost;

  bool get _canRestartRound =>
      !_busy && _gameOver && _players.length >= 2 && _isHost;

  bool get _canBet =>
      !_busy && _gameStarted && !_gameOver && _bettingOpen && !_joinedMidRound;

  bool get _canPlay =>
      _gameStarted && !_gameOver && !_bettingOpen && !_busy && _isMyTurn;

  int get _playersStillToBet {
    if (!_bettingOpen) return 0;
    return _players.where((p) {
      final joinedMidRound = (p["joined_mid_round"] ?? false) as bool;
      final bet = ((p["bet"] ?? 0) as num).toInt();
      return !joinedMidRound && bet <= 0;
    }).length;
  }

  String get _turnPlayerName {
    if (_turnPlayerId == null) return 'Player';
    try {
      final p = _players.firstWhere((e) => e["id"] == _turnPlayerId);
      return (p["name"] ?? 'Player').toString();
    } catch (_) {
      return 'Player';
    }
  }

  String get _hostName {
    if (_hostPlayerId == null) return '-';
    try {
      final p = _players.firstWhere((e) => e["id"] == _hostPlayerId);
      return (p["name"] ?? '-').toString();
    } catch (_) {
      return '-';
    }
  }

  int get _myCoinDelta {
    final result = _myPlayer?["result"]?.toString();
    if (result == 'Win') return _myBet;
    if (result == 'Loss') return -_myBet;
    return 0;
  }
//Creates top level message such as waiting for players, your turn etc
  String _heroText() {
    if (!_gameStarted) {
      if (_players.length < 2) return 'Waiting for more players';
      return _isHost ? 'You can start the round' : 'Waiting for host to start';
    }

    if (_gameOver) {
      final result = _myPlayer?["result"]?.toString() ?? '-';
      return 'Round complete • $result';
    }

    if (_bettingOpen) {
      if (_joinedMidRound) return 'You joined mid-round';
      if (_myBet > 0) {
        if (_playersStillToBet > 0) {
          return 'Bet locked • waiting for $_playersStillToBet player(s)';
        }
        return 'Bet locked';
      }
      return 'Place your bet';
    }

    if (_isMyTurn) return 'Your turn';
    if (_turnPlayerId == null) return 'Dealer resolving';
    return 'Waiting for $_turnPlayerName';
  }
//Flutter requests a bet, then blackjack py validates it server side. Sends chosen bet to backend
  void _sendBet(int amount) {
    if (amount > _coins) {
      setState(() {
        _status = "Not enough coins for that bet.";
      });
      return;
    }

    setState(() {
      _selectedBet = amount;
      _busy = true;
      _status = 'Sending bet of $amount...';
    });

    _ws.sendJson({
      "type": "bet",
      "amount": amount,
    });
  }
//FireStore reference for recording of Results, coins, stats
  Future<void> _saveMatchStatsAndCoins(String resultStr) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not signed in");

    final myBet = ((_myPlayer?["bet"] ?? 0) as num).toInt();
    final myTotal = ((_myPlayer?["total"] ?? 0) as num).toInt();
    final dealerTotal = _dealerTotal ?? 0;

    final rawOpponentCount =
        _players.where((p) => p["id"] != widget.playerId).length;
    final opponentCount = rawOpponentCount < 1 ? 1 : rawOpponentCount;

    final coinDelta = resultStr == 'Win'
        ? myBet
        : resultStr == 'Loss'
        ? -myBet
        : 0;
//User ref collection matches and stats
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
          singleplayerGames = 0;
          multiplayerGames = gamesPlayed;
          singleplayerWins = 0;
          multiplayerWins = wins;
        }
      }

      if (userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>;
        coins = ((userData['coins'] ?? 0) as num).toInt();
      }

      gamesPlayed += 1;
      multiplayerGames += 1;

      if (resultStr == 'Win') {
        wins += 1;
        multiplayerWins += 1;
        coinsWon += myBet;
        currentWinStreak += 1;
        if (myBet > biggestWin) biggestWin = myBet;
      } else if (resultStr == 'Loss') {
        losses += 1;
        coinsLost += myBet;
        currentWinStreak = 0;
      } else {
        pushes += 1;
        currentWinStreak = 0;
      }

      if (currentWinStreak > bestWinStreak) {
        bestWinStreak = currentWinStreak;
      }

      if (myBet > highestBet) {
        highestBet = myBet;
      }

      netCoins = coinsWon - coinsLost;

      coins += coinDelta;
      if (coins < 0) coins = 0;

      final matchDoc = matchesRef.doc();
      tx.set(matchDoc, {
        'gameType': 'Blackjack Multiplayer',
        'mode': 'multiplayer',
        'result': resultStr,
        'bet': myBet,
        'coinDelta': coinDelta,
        'playerTotal': myTotal,
        'dealerTotal': dealerTotal,
        'roomId': widget.roomId,
        'opponentCount': opponentCount,
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
//Result color coding
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
//Converts players flags like busted, stood blackjack etc into readable label and color
  String _seatStateText(Map<String, dynamic>? player) {
    if (player == null) return 'Waiting';

    final joinedMidRound = (player["joined_mid_round"] ?? false) as bool;
    final bet = ((player["bet"] ?? 0) as num).toInt();
    final busted = (player["busted"] ?? false) as bool;
    final blackjack = (player["blackjack"] ?? false) as bool;
    final stood = (player["stood"] ?? false) as bool;
    final result = player["result"]?.toString();
    final isTurn = player["id"] == _turnPlayerId;

    if (joinedMidRound) return 'Next round';
    if (_gameOver && result != null) return result;
    if (_bettingOpen) return bet > 0 ? 'Bet locked' : 'Choosing bet';
    if (busted) return 'Busted';
    if (blackjack) return 'Blackjack';
    if (stood) return 'Stood';
    if (isTurn) return 'Playing';
    return 'Waiting';
  }

  Color _seatStateColor(Map<String, dynamic>? player) {
    final text = _seatStateText(player);
    switch (text) {
      case 'Win':
        return Colors.green.shade300;
      case 'Loss':
        return Colors.red.shade300;
      case 'Push':
        return Colors.orange.shade300;
      case 'Busted':
        return Colors.red.shade300;
      case 'Blackjack':
        return Colors.green.shade300;
      case 'Bet locked':
        return Colors.orange.shade300;
      case 'Playing':
        return Colors.green.shade300;
      default:
        return Colors.white70;
    }
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
//Renders card hand for dealer opponents and current player
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
//Builds hero header for multiplayer room, status, room id etc
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
              _pill('MULTIPLAYER BLACKJACK'),
              _pill('Room ${widget.roomId}'),
              _pill('Coins $_coins'),
              _pill('Players ${_players.length}'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _heroText(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gameOver
                  ? _resultColor(_myPlayer?["result"]?.toString())
                  : (_isMyTurn ? Colors.green.shade300 : Colors.white),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isHost
                ? 'You are hosting this table.'
                : 'Host: $_hostName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
//Shows dealers cards and total only when revealed
  Widget _buildDealerSeat() {
    final dealerTotalText =
    _dealerRevealed ? (_dealerTotal?.toString() ?? '-') : '??';

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
          const SizedBox(height: 8),
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
//Builds one opponent panel with cards, status, bet and turn
  Widget _buildOpponentSeat(Map<String, dynamic> player) {
    final isTurn = player["id"] == _turnPlayerId;
    final isHost = player["id"] == _hostPlayerId;
    final joinedMidRound = (player["joined_mid_round"] ?? false) as bool;
    final name = (player["name"] ?? 'Player').toString();
    final cards = List<String>.from(player["cards"] ?? []);
    final total = ((player["total"] ?? 0) as num).toInt();
    final result = player["result"]?.toString();
    final bet = ((player["bet"] ?? 0) as num).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isTurn ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTurn ? Colors.green.shade300 : Colors.white12,
          width: isTurn ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 6),
                _badge(
                  'HOST',
                  fg: Colors.deepPurple.shade100,
                  bg: Colors.deepPurple.withOpacity(0.25),
                ),
              ],
              if (isTurn) ...[
                const SizedBox(width: 6),
                _badge(
                  'TURN',
                  fg: Colors.green.shade100,
                  bg: Colors.green.withOpacity(0.20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildFanHand(
                cards,
                cardWidth: 44,
                cardHeight: 66,
                overlap: 14,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _seatStateText(player),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _seatStateColor(player),
            ),
          ),
          const SizedBox(height: 4),
          if (joinedMidRound)
            const Text(
              'Joining on next round',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            )
          else
            _buildCompactInfoLine(
              bet: bet,
              total: total,
              result: result,
            ),
        ],
      ),
    );
  }
//Display up to 2 opponents using _opponents.take(2)
  Widget _buildOpponentsRow() {
    final opponents = _opponents;
    if (opponents.isEmpty) {
      return const SizedBox.shrink();
    }

    if (opponents.length == 1) {
      return Center(
        child: SizedBox(
          width: 210,
          child: _buildOpponentSeat(opponents[0]),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildOpponentSeat(opponents[0])),
        const SizedBox(width: 10),
        Expanded(child: _buildOpponentSeat(opponents[1])),
      ],
    );
  }
//Builds the signed in players seat with cards total bet etc
  Widget _buildMySeat() {
    final me = _myPlayer;
    final cards = List<String>.from(me?["cards"] ?? []);
    final total = ((me?["total"] ?? 0) as num).toInt();
    final result = me?["result"]?.toString();
    final myName = (me?["name"] ?? widget.playerName).toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isMyTurn ? Colors.green.shade300 : Colors.white24,
          width: _isMyTurn ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$myName (YOU)',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_isHost)
                _badge(
                  'HOST',
                  fg: Colors.deepPurple.shade100,
                  bg: Colors.deepPurple.withOpacity(0.25),
                ),
              if (_isMyTurn) ...[
                const SizedBox(width: 8),
                _badge(
                  'TURN',
                  fg: Colors.green.shade100,
                  bg: Colors.green.withOpacity(0.20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                'Coins: $_coins',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'Bet: $_myBet',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildFanHand(
              cards,
              cardWidth: 64,
              cardHeight: 96,
              overlap: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _seatStateText(me),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _seatStateColor(me),
            ),
          ),
          const SizedBox(height: 4),
          _buildCompactInfoLine(
            bet: _myBet,
            total: total,
            result: result,
          ),
        ],
      ),
    );
  }
//Multiplayer betting ui linked to websocket bet action
  Widget _buildBetSelector() {
    Widget chip(int amount) {
      final selected = _selectedBet == amount;
      final disabled = amount > _coins;

      return ChoiceChip(
        label: Text('$amount'),
        selected: selected,
        onSelected: _canBet && !disabled ? (_) => _sendBet(amount) : null,
      );
    }

    String rightText;
    if (_joinedMidRound) {
      rightText = 'Next round';
    } else if (_myBet > 0) {
      rightText = 'Bet placed';
    } else {
      rightText = 'Choose bet';
    }

    String helperText;
    if (_joinedMidRound) {
      helperText =
      'You joined after this round started and will play next round.';
    } else if (_myBet > 0) {
      if (_playersStillToBet > 0) {
        helperText =
        'Your bet: $_myBet • Waiting for $_playersStillToBet player(s)';
      } else {
        helperText = 'Your bet: $_myBet • Waiting for round to begin';
      }
    } else {
      helperText = 'Tap a chip to lock in your bet.';
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
              const Expanded(
                child: Text(
                  'Place your bet',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                rightText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              helperText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
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
//Shows final result after game_over from backend
  Widget _buildRoundSummary() {
    if (!_gameOver) return const SizedBox.shrink();

    final result = _myPlayer?["result"]?.toString() ?? '-';
    final myTotal = ((_myPlayer?["total"] ?? 0) as num).toInt();
    final dealerTotal = _dealerTotal ?? 0;
    final coinDelta = _myCoinDelta;
    final coinText = coinDelta > 0
        ? '+$coinDelta coins'
        : coinDelta < 0
        ? '$coinDelta coins'
        : '0 coins';

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
            coinText,
            style: TextStyle(
              color: _resultColor(result),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Your total: $myTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Dealer: $dealerTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Bet: $_myBet',
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
//Builds action button from backend phase / ws send start + action
  Widget _buildControls() {
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

    if (!_gameStarted) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: style(const Color(0xFF3B82F6)),
          onPressed: _canStartRound ? _ws.sendStart : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            _players.length < 2
                ? 'Need 2 players to start'
                : (_isHost ? 'Start Round' : 'Waiting for host'),
          ),
        ),
      );
    }

    if (_gameOver) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: style(const Color(0xFF3B82F6)),
          onPressed: _canRestartRound ? _ws.sendStart : null,
          icon: const Icon(Icons.replay),
          label: Text(
            _isHost ? 'Start New Round' : 'Waiting for host to restart',
          ),
        ),
      );
    }

    if (_bettingOpen) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: style(const Color(0xFF0F766E)),
          onPressed: null,
          icon: const Icon(Icons.payments),
          label: Text(
            _joinedMidRound
                ? 'Joining Next Round'
                : _myBet > 0
                ? 'Bet Locked'
                : 'Choose Bet',
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: style(const Color(0xFFEF4444)),
            onPressed: _canPlay ? () => _ws.sendAction("hit") : null,
            icon: const Icon(Icons.add),
            label: const Text('Hit'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: style(const Color(0xFF2563EB)),
            onPressed: _canPlay ? () => _ws.sendAction("stand") : null,
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
        title: Text('Blackjack Table (${widget.roomId})'),
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
                const SizedBox(height: 12),
                _buildDealerSeat(),
                const SizedBox(height: 14),
                _buildOpponentsRow(),
                if (_opponents.isNotEmpty) const SizedBox(height: 14),
                _buildMySeat(),
                const SizedBox(height: 10),
                if (_gameStarted && !_gameOver && _bettingOpen) ...[
                  _buildBetSelector(),
                  const SizedBox(height: 10),
                ],
                if (_gameOver) ...[
                  _buildRoundSummary(),
                  const SizedBox(height: 10),
                ],
                _buildStatusBar(),
                const SizedBox(height: 10),
                _buildControls(),
                if (!_gameStarted) ...[
                  const SizedBox(height: 10),
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
                    child: const Text(
                      'Round flow:\n1. Host starts the round\n2. Cards are dealt\n3. Players place bets\n4. Turns are played\n5. Results save automatically',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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