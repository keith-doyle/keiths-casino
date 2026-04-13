import 'dart:async';
import 'dart:convert';

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
  String _phase = 'waiting';
  int _pot = 0;
  int _currentBet = 0;

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() {
    _ws.connectToPokerTable(roomId: widget.roomId);

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
          if (!mounted) return;
          setState(() {
            _players = List<Map<String, dynamic>>.from(msg["players"] ?? []);
            _communityCards = List<String>.from(msg["community_cards"] ?? []);
            _hostPlayerId = msg["host_player_id"]?.toString();
            _turnPlayerId = msg["turn_player_id"]?.toString();
            _status = (msg["status"] ?? "Connected").toString();
            _gameStarted = (msg["game_started"] ?? false) as bool;
            _phase = (msg["phase"] ?? "waiting").toString();
            _pot = ((msg["pot"] ?? 0) as num).toInt();
            _currentBet = ((msg["current_bet"] ?? 0) as num).toInt();
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

  bool get _isHost => _hostPlayerId == widget.playerId;
  bool get _isMyTurn => _turnPlayerId == widget.playerId;

  Map<String, dynamic>? get _myPlayer {
    try {
      return _players.firstWhere((p) => (p["id"] ?? "").toString() == widget.playerId);
    } catch (_) {
      return null;
    }
  }

  List<String> get _myCards => List<String>.from(_myPlayer?["cards"] ?? []);
  int get _myChips => (((_myPlayer?["chips"] ?? 0) as num).toInt());
  int get _myCurrentBet => (((_myPlayer?["current_bet"] ?? 0) as num).toInt());

  String _phaseLabel() {
    return _phase.toUpperCase();
  }

  void _sendAction(String action, {int amount = 0}) {
    _ws.sendJson({
      "type": "action",
      "action": action,
      "amount": amount,
    });
  }

  String _turnLabel() {
    if (!_gameStarted) return 'Waiting to start';
    if (_turnPlayerId == null) return 'No active turn';
    try {
      final player = _players.firstWhere(
            (p) => (p["id"] ?? "").toString() == _turnPlayerId,
      );
      final name = (player["name"] ?? 'Player').toString();
      return _isMyTurn ? 'Your turn' : '$name\'s turn';
    } catch (_) {
      return 'Turn active';
    }
  }

  Widget _buildInfoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
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

  Widget _buildFanHand(
      List<String> cards, {
        required double cardWidth,
        required double cardHeight,
        required double overlap,
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
              width: cardWidth,
              height: cardHeight,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final playerId = (player["id"] ?? "").toString();
    final name = (player["name"] ?? "Player").toString();
    final isYou = playerId == widget.playerId;
    final isHost = playerId == _hostPlayerId;
    final isTurn = playerId == _turnPlayerId;
    final folded = (player["folded"] ?? false) as bool;
    final acted = (player["has_acted_this_round"] ?? false) as bool;
    final cardCount = ((player["card_count"] ?? 0) as num).toInt();
    final chips = ((player["chips"] ?? 0) as num).toInt();
    final currentBet = ((player["current_bet"] ?? 0) as num).toInt();

    String subtitle = folded
        ? 'Folded • Chips: $chips'
        : 'Cards: $cardCount • Chips: $chips • Bet: $currentBet';

    if (!folded && acted && _gameStarted) {
      subtitle = 'Acted • Cards: $cardCount • Chips: $chips • Bet: $currentBet';
    }

    return Card(
      color: Colors.white.withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(name),
        subtitle: Text(subtitle),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (isHost)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'HOST',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.deepPurple,
                    fontSize: 11,
                  ),
                ),
              ),
            if (isTurn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'TURN',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                    fontSize: 11,
                  ),
                ),
              ),
            if (isYou)
              const Text(
                'YOU',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    if (!_gameStarted) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy || !_isHost || _players.length < 2 ? null : _ws.sendStart,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            _players.length < 2
                ? 'Need 2 players to start'
                : (_isHost ? 'Start Round' : 'Waiting for host'),
          ),
        ),
      );
    }

    if (_isMyTurn) {
      final canCheck = _currentBet == _myCurrentBet;
      final raiseAmount = _currentBet + 50;
      final canRaise = _myChips >= (raiseAmount - _myCurrentBet);
      final canCall = _myChips >= (_currentBet - _myCurrentBet);

      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || !canCheck ? null : () => _sendAction('check'),
                  icon: const Icon(Icons.check),
                  label: const Text('Check'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || !canCall ? null : () => _sendAction('call'),
                  icon: const Icon(Icons.call_made),
                  label: const Text('Call'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _sendAction('fold'),
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
                  icon: const Icon(Icons.arrow_upward),
                  label: Text('Raise to $raiseAmount'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_bottom),
        label: Text(_turnLabel()),
      ),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildInfoPill('Room ${widget.roomId}'),
                    _buildInfoPill('Players: ${_players.length}'),
                    _buildInfoPill(_isHost ? 'Host: You' : 'Host assigned'),
                    _buildInfoPill('Phase: ${_phaseLabel()}'),
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
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _turnLabel(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isMyTurn ? Colors.green.shade300 : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Community Cards',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildFanHand(
                          _communityCards,
                          cardWidth: 58,
                          cardHeight: 88,
                          overlap: 24,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pot: $_pot',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
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
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Your Hole Cards',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildFanHand(
                          _myCards,
                          cardWidth: 64,
                          cardHeight: 96,
                          overlap: 30,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your chips: $_myChips • Your bet: $_myCurrentBet',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _players.isEmpty
                      ? Center(
                    child: Text(
                      _busy ? 'Joining poker table...' : 'No players connected',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                      : ListView.builder(
                    itemCount: _players.length,
                    itemBuilder: (context, index) {
                      return _buildPlayerCard(_players[index]);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _buildControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}