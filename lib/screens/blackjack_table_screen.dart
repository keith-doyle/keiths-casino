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

  bool _gameStarted = false;
  bool _gameOver = false;
  bool _dealerRevealed = false;
  bool _busy = true;
  bool _savedThisRound = false;

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

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

        if (type == "table_state") {
          final players = List<Map<String, dynamic>>.from(msg["players"] ?? []);

          if (!mounted) return;
          setState(() {
            _dealerCards = List<String>.from(msg["dealer_cards"] ?? []);
            _dealerTotal = msg["dealer_total"] as int?;
            _players = players;

            _status = (msg["status"] ?? "").toString();
            _hostPlayerId = msg["host_player_id"]?.toString();
            _turnPlayerId = msg["turn_player_id"]?.toString();

            _gameStarted = (msg["game_started"] ?? false) as bool;
            _gameOver = (msg["game_over"] ?? false) as bool;
            _dealerRevealed = (msg["dealer_revealed"] ?? false) as bool;

            _busy = false;
          });

          if (!_gameStarted) {
            _savedThisRound = false;
          }

          if (_gameOver && !_savedThisRound) {
            final me = _myPlayer;
            final result = me?["result"]?.toString();

            if (result == "Win" || result == "Loss" || result == "Push") {
              _savedThisRound = true;
              try {
                await _saveMatchAndStats(result!);
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _status = "Match/stat save failed: $e";
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

  Future<void> _saveMatchAndStats(String resultStr) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not signed in");

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final matchesRef = userRef.collection('matches');
    final statsRef = userRef.collection('stats').doc('blackjack');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final statsSnap = await tx.get(statsRef);

      int gamesPlayed = 0;
      int wins = 0;
      int losses = 0;
      int pushes = 0;

      if (statsSnap.exists) {
        final existing = statsSnap.data() as Map<String, dynamic>;
        gamesPlayed = ((existing['gamesPlayed'] ?? 0) as num).toInt();
        wins = ((existing['wins'] ?? 0) as num).toInt();
        losses = ((existing['losses'] ?? 0) as num).toInt();
        pushes = ((existing['pushes'] ?? 0) as num).toInt();
      }

      gamesPlayed += 1;
      if (resultStr == 'Win') wins += 1;
      if (resultStr == 'Loss') losses += 1;
      if (resultStr == 'Push') pushes += 1;

      final matchDoc = matchesRef.doc();
      tx.set(matchDoc, {
        'gameType': 'Blackjack Multiplayer',
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
    });
  }

  Color _resultColor(String? result) {
    switch (result) {
      case 'Win':
        return Colors.green.shade700;
      case 'Loss':
        return Colors.red.shade700;
      case 'Push':
        return Colors.orange.shade700;
      default:
        return Colors.black87;
    }
  }

  Widget _badge(
      String label, {
        required Color fg,
        required Color bg,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11,
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
      return const SizedBox.shrink();
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

  Widget _buildDealerSeat() {
    final dealerTotalText =
    _dealerRevealed ? (_dealerTotal?.toString() ?? '-') : '??';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Dealer',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _buildFanHand(
            _dealerCards,
            cardWidth: 72,
            cardHeight: 108,
            overlap: 42,
            hideDealerSecond: !_dealerRevealed && _dealerCards.length >= 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Dealer total: $dealerTotalText',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildOpponentSeat(
      Map<String, dynamic> player, {
        required bool alignLeft,
      }) {
    final isTurn = player["id"] == _turnPlayerId;
    final isHost = player["id"] == _hostPlayerId;
    final name = (player["name"] ?? 'Player').toString();
    final cards = List<String>.from(player["cards"] ?? []);
    final total = player["total"] ?? 0;
    final result = player["result"]?.toString();

    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isTurn
            ? Colors.white.withOpacity(0.18)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTurn ? Colors.green.shade300 : Colors.white24,
          width: isTurn ? 1.4 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
        alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              if (!alignLeft && (isHost || isTurn)) ...[
                if (isTurn)
                  _badge(
                    'TURN',
                    fg: Colors.green.shade100,
                    bg: Colors.green.withOpacity(0.20),
                  ),
                if (isTurn && isHost) const SizedBox(width: 6),
                if (isHost)
                  _badge(
                    'HOST',
                    fg: Colors.deepPurple,
                    bg: Colors.deepPurple.withOpacity(0.18),
                  ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  name,
                  textAlign: alignLeft ? TextAlign.left : TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (alignLeft && (isHost || isTurn)) ...[
                const SizedBox(width: 8),
                if (isHost)
                  _badge(
                    'HOST',
                    fg: Colors.deepPurple,
                    bg: Colors.deepPurple.withOpacity(0.18),
                  ),
                if (isTurn && isHost) const SizedBox(width: 6),
                if (isTurn)
                  _badge(
                    'TURN',
                    fg: Colors.green.shade100,
                    bg: Colors.green.withOpacity(0.20),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: !alignLeft,
            child: _buildFanHand(
              cards,
              cardWidth: 72,
              cardHeight: 108,
              overlap: 22,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: $total',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Result: ${result ?? "-"}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: result == null ? Colors.white : _resultColor(result),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMySeat() {
    final me = _myPlayer;
    final cards = List<String>.from(me?["cards"] ?? []);
    final total = me?["total"] ?? 0;
    final result = me?["result"]?.toString();
    final myName = (me?["name"] ?? widget.playerName).toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isMyTurn ? Colors.green.shade300 : Colors.white24,
          width: _isMyTurn ? 1.6 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$myName (YOU)',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_isHost)
                _badge(
                  'HOST',
                  fg: Colors.deepPurple,
                  bg: Colors.deepPurple.withOpacity(0.18),
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
          const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildFanHand(
                cards,
                cardWidth: 72,
                cardHeight: 108,
                overlap: 36,
              ),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Total: $total',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 18),
              Text(
                'Result: ${result ?? "-"}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: result == null ? Colors.white : _resultColor(result),
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

  Widget _buildControls() {
    final canStart = !_gameStarted && !_busy && _isHost && _players.length >= 2;
    final canRestart = _gameOver && !_busy && _isHost && _players.length >= 2;
    final canPlay = _gameStarted && !_gameOver && !_busy && _isMyTurn;

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
          onPressed: canStart ? _ws.sendStart : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            _players.length < 2
                ? 'Need 2 players to start'
                : (_isHost ? 'Start Game' : 'Waiting for host'),
          ),
        ),
      );
    }

    if (_gameOver) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: style(const Color(0xFF3B82F6)),
          onPressed: canRestart ? _ws.sendStart : null,
          icon: const Icon(Icons.replay),
          label: Text(
            _isHost ? 'Start New Round' : 'Waiting for host to restart',
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: style(const Color(0xFFEF4444)),
            onPressed: canPlay ? () => _ws.sendAction("hit") : null,
            child: const Text('Hit'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: style(const Color(0xFF2563EB)),
            onPressed: canPlay ? () => _ws.sendAction("stand") : null,
            child: const Text('Stand'),
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
    final leftOpponent = _opponents.isNotEmpty ? _opponents[0] : null;
    final rightOpponent = _opponents.length > 1 ? _opponents[1] : null;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;

              final sideSeatTop = height * 0.28;
              final bottomSeatHeight = height * 0.28;

              return Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Column(
                        children: [

                          const SizedBox(height: 6),

                          _buildDealerSeat(),

                          const Spacer(),

                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [

                              _buildMySeat(),

                              const SizedBox(height: 10),

                              _buildStatusBar(),

                              const SizedBox(height: 10),

                              _buildControls(),

                            ],
                          ),

                        ],
                      ),
                    ),
                  ),
                  if (leftOpponent != null)
                    Positioned(
                      left: 10,
                      top: sideSeatTop,
                      width: 140,
                      child: _buildOpponentSeat(
                        leftOpponent,
                        alignLeft: true,
                      ),
                    ),

                  if (rightOpponent != null)
                    Positioned(
                      right: 10,
                      top: sideSeatTop,
                      width: 140,
                      child: _buildOpponentSeat(
                        rightOpponent,
                        alignLeft: false,
                      ),
                    ),

                  Positioned(
                    top: height * 0.42,
                    left: width * 0.32,
                    right: width * 0.32,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        'Room ${widget.roomId}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}