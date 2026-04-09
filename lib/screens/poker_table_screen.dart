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
  String _status = 'Connecting...';
  String? _hostPlayerId;
  bool _busy = true;
  bool _gameStarted = false;
  String _phase = 'waiting';

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
            _hostPlayerId = msg["host_player_id"]?.toString();
            _status = (msg["status"] ?? "Connected").toString();
            _gameStarted = (msg["game_started"] ?? false) as bool;
            _phase = (msg["phase"] ?? "waiting").toString();
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

  Map<String, dynamic>? get _myPlayer {
    try {
      return _players.firstWhere((p) => (p["id"] ?? "").toString() == widget.playerId);
    } catch (_) {
      return null;
    }
  }

  List<String> get _myCards => List<String>.from(_myPlayer?["cards"] ?? []);

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
    final folded = (player["folded"] ?? false) as bool;
    final cardCount = ((player["card_count"] ?? 0) as num).toInt();

    return Card(
      color: Colors.white.withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(name),
        subtitle: Text(
          folded ? 'Folded • Cards: $cardCount' : 'Cards: $cardCount',
        ),
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
    if (_gameStarted) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline),
          label: Text('Round Active • ${_phase.toUpperCase()}'),
        ),
      );
    }

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
                    _buildInfoPill('Phase: ${_phase.toUpperCase()}'),
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