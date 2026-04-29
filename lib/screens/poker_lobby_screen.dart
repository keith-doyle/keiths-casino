import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import 'invite_friend_screen.dart';
import 'poker_table_screen.dart';

class PokerLobbyScreen extends StatefulWidget {
  final String roomId;

  const PokerLobbyScreen({
    super.key,
    required this.roomId,
  });

  @override
  State<PokerLobbyScreen> createState() => _PokerLobbyScreenState();
}

class _PokerLobbyScreenState extends State<PokerLobbyScreen> {
  final BlackjackWsService _ws = BlackjackWsService();
  StreamSubscription? _sub;

  String? _roomId;
  String? _youId;
  String? _hostPlayerId;
  List<Map<String, dynamic>> _players = [];

  String _status = "Connecting...";
  bool _busy = true;

  String _myName = "-";

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await _connectAndListen();
    });
  }

  Future<String> _fetchUsernameForUid(String uid) async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('usernames')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        final data = q.docs.first.data();
        final username = (data['username'] ?? '').toString().trim();
        if (username.isNotEmpty) return username;
      }
    } catch (_) {}

    return uid.length >= 6 ? uid.substring(0, 6) : uid;
  }

  Future<void> _openInviteSheet() async {
    final roomId = _roomId;
    if (roomId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InviteFriendScreen(
          roomId: roomId,
          game: 'poker',
          fromUsername: _myName,
          players: List<Map<String, dynamic>>.from(_players),
        ),
      ),
    );
  }

  Future<void> _connectAndListen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        "test_${DateTime.now().millisecondsSinceEpoch}";

    final username = await _fetchUsernameForUid(uid);
    if (!mounted) return;

    setState(() {
      _myName = username;
    });

    final roomId = widget.roomId.trim().toUpperCase();
    _roomId = roomId;

    _ws.connectToRoom(roomId: roomId);

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
          _ws.join(playerId: uid, playerName: _myName);

          if (!mounted) return;
          setState(() {
            _status = "Connected. Joining room...";
          });
          return;
        }

        if (type == "table_state") {
          if (!mounted) return;
          setState(() {
            _youId = (msg["you"]?["id"])?.toString();
            _hostPlayerId = msg["host_player_id"]?.toString();
            _players = List<Map<String, dynamic>>.from(msg["players"] ?? []);
            _status = "In room ${msg["room_id"]}";
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

  String _compactStatusText() {
    if (_busy) return 'Joining lobby...';
    if (_players.length < 2) return 'Waiting for more players';
    return 'Lobby ready';
  }

  Color _compactStatusColor() {
    if (_busy) return Colors.orange.shade300;
    if (_players.length < 2) return Colors.orange.shade300;
    return Colors.green.shade300;
  }

  String _hostName() {
    if (_hostPlayerId == null || _players.isEmpty) return '-';

    try {
      final host = _players.firstWhere(
            (p) => (p["id"] ?? "").toString() == _hostPlayerId,
      );
      return (host["name"] ?? '-').toString();
    } catch (_) {
      return '-';
    }
  }

  bool get _isHost {
    if (_youId == null || _hostPlayerId == null) return false;
    return _youId == _hostPlayerId;
  }

  Widget _buildLobbyPill(String text, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: textColor ?? Colors.white,
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildLobbyPill('POKER LOBBY'),
              _buildLobbyPill('Room ${_roomId ?? "-"}'),
              _buildLobbyPill('Players ${_players.length}'),
              _buildLobbyPill(_isHost ? 'Host: You' : 'Host: ${_hostName()}'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _compactStatusText(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _compactStatusColor(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _players.length < 2
                ? 'Invite someone or wait for another player to join.'
                : 'Everyone is ready to move into the poker table.',
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

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: _compactStatusColor(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerTile(Map<String, dynamic> p) {
    final pid = (p["id"] ?? "").toString();
    final name = (p["name"] ?? pid).toString();
    final isYou = (_youId != null && pid == _youId);
    final isHost = (_hostPlayerId != null && pid == _hostPlayerId);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isYou ? Colors.green.withOpacity(0.5) : Colors.white12,
          width: isYou ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white.withOpacity(0.10),
            child: const Icon(
              Icons.person,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isHost ? 'Room host' : 'Player in lobby',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isHost)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'HOST',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.deepPurple.shade100,
                  fontSize: 11,
                ),
              ),
            ),
          if (isYou)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.20),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'YOU',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade100,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Players in Lobby',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          if (_players.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                _busy ? 'Joining lobby...' : 'No players in lobby',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ListView.builder(
              itemCount: _players.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, i) {
                final p = _players[i];
                return _buildPlayerTile(p);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'Lobby flow:\n1. Join the room\n2. Invite friends if needed\n3. Wait until at least 2 players are present\n4. Enter the table',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
          height: 1.35,
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
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final canEnter =
        _roomId != null && _players.isNotEmpty && currentUid.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Poker Lobby"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _openInviteSheet,
            tooltip: 'Invite friend',
          ),
        ],
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildHeroCard(),
                const SizedBox(height: 12),
                _buildStatusCard(),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildPlayersSection(),
                        const SizedBox(height: 12),
                        _buildBottomHint(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canEnter
                        ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PokerTableScreen(
                            roomId: _roomId!,
                            playerId: currentUid,
                            playerName: _myName,
                          ),
                        ),
                      );
                    }
                        : null,
                    icon: const Icon(Icons.casino),
                    label: const Text("Enter Table"),
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "Working...",
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}