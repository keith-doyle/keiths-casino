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
  bool _roundOver = false;
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

        if (type == "table_state") {
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
            _bigBlindAmount =
                ((msg["big_blind_amount"] ?? 0) as num).toInt();

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

  String _winnerLabel() {
    if (_iWon) {
      return _winningHandName == null
          ? 'You won the round'
          : 'You won with $_winningHandName';
    }

    try {
      final winner =
      _players.firstWhere((p) => p["id"] == _winnerPlayerId);
      final name = (winner["name"] ?? 'Player').toString();
      return _winningHandName == null
          ? '$name won the round'
          : '$name won with $_winningHandName';
    } catch (_) {
      return 'Round complete';
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
          fontSize: 11,
        ),
      ),
    );
  }

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
            padding: const EdgeInsets.only(right: 4),
            child: PlayingCardWidget(
              cardId: c,
              width: 42,
              height: 62,
            ),
          ),
        )
            .toList(),
      ),
    );
  }

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

    return Card(
      color: isTurn
          ? Colors.green.withOpacity(0.25)
          : isWinner
          ? Colors.green.withOpacity(0.18)
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              title: Text((player["name"] ?? 'Player').toString()),
              subtitle: Text(subtitle),
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isDealer) _badge('D', Colors.orange),
                  if (isSmallBlind) _badge('SB', Colors.blue),
                  if (isBigBlind) _badge('BB', Colors.red),
                  if (isWinner) _badge('WIN', Colors.green),
                  if (isYou) _badge('YOU', Colors.deepPurple),
                ],
              ),
            ),
            if (_roundOver && cards.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSmallCards(cards),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityCards() {
    if (_communityCards.isEmpty) {
      return const Text(
        'No community cards yet',
        style: TextStyle(color: Colors.white70),
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
            child: PlayingCardWidget(cardId: c),
          ),
        )
            .toList(),
      ),
    );
  }

  Widget _buildMyCards() {
    if (_myCards.isEmpty) {
      return const Text(
        'No hole cards yet',
        style: TextStyle(color: Colors.white70),
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
            child: PlayingCardWidget(cardId: c),
          ),
        )
            .toList(),
      ),
    );
  }

  Widget _buildPrimaryActionArea() {
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
                onPressed: _busy || !canCheck
                    ? null
                    : () => _sendAction('check'),
                icon: const Icon(Icons.check),
                label: const Text('Check'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !canCall
                    ? null
                    : () => _sendAction('call'),
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

  @override
  void dispose() {
    _sub?.cancel();
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final headerTextStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

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
                    _badge('Room ${widget.roomId}', Colors.white),
                    _badge('Players ${_players.length}', Colors.white),
                    _badge('Blinds $_smallBlindAmount / $_bigBlindAmount',
                        Colors.white),
                    _badge('Phase ${_phase.toUpperCase()}', Colors.white),
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
                    _buildStatusText(),
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
                      borderRadius: BorderRadius.circular(14),
                      border:
                      Border.all(color: Colors.green.withOpacity(0.45)),
                    ),
                    child: Text(
                      _winnerLabel(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      Text('Community Cards', style: headerTextStyle),
                      const SizedBox(height: 10),
                      _buildCommunityCards(),
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      Text('Your Hole Cards', style: headerTextStyle),
                      const SizedBox(height: 10),
                      _buildMyCards(),
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
                      _busy
                          ? 'Joining poker table...'
                          : 'No players connected',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                      : ListView.builder(
                    itemCount: _players.length,
                    itemBuilder: (_, i) => _buildPlayerCard(_players[i]),
                  ),
                ),
                const SizedBox(height: 12),
                _buildPrimaryActionArea(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}