import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import 'blackjack_table_screen.dart';

class BlackjackLobbyScreen extends StatefulWidget {
  final String roomId;

  const BlackjackLobbyScreen({
    super.key,
    required this.roomId,
  });

  @override
  State<BlackjackLobbyScreen> createState() => _BlackjackLobbyScreenState();
}

class _BlackjackLobbyScreenState extends State<BlackjackLobbyScreen> {
  final BlackjackWsService _ws = BlackjackWsService();
  StreamSubscription? _sub;

  String? _roomId;
  String? _youId;
  List<Map<String, dynamic>> _players = [];

  String _status = "Connecting...";
  bool _busy = true;

  String _myName = "-";

  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = false;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await _connectAndListen();
      await _loadFriends();
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

  Future<void> _loadFriends() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loadingFriends = true);

    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final friendIds = List<String>.from(userDoc.data()?['friends'] ?? []);

      final loaded = <Map<String, dynamic>>[];

      for (final fid in friendIds) {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(fid).get();
        if (!doc.exists) continue;

        final data = doc.data() ?? {};
        loaded.add({
          'uid': fid,
          'username': (data['username'] ?? 'Unknown').toString(),
        });
      }

      loaded.sort(
            (a, b) => a['username']
            .toString()
            .toLowerCase()
            .compareTo(b['username'].toString().toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _friends = loaded;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load friends')),
      );
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _sendGameInvite(Map<String, dynamic> friend) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final roomId = _roomId;
    if (currentUid == null || roomId == null) return;

    final friendUid = (friend['uid'] ?? '').toString();
    final friendUsername = (friend['username'] ?? 'Friend').toString();

    if (friendUid.isEmpty) return;

    try {
      final notificationId = 'game_invite_${currentUid}_$roomId';
      final notifRef = FirebaseFirestore.instance
          .collection('users')
          .doc(friendUid)
          .collection('notifications')
          .doc(notificationId);

      await notifRef.set({
        'type': 'game_invite',
        'fromUid': currentUid,
        'fromUsername': _myName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'roomId': roomId,
        'game': 'blackjack',
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite sent to $friendUsername')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send invite: ${e.message ?? e.code}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send invite')),
      );
    }
  }

  void _openInviteSheet() {
    if (_friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No friends available to invite')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Invite a Friend',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final friend = _friends[i];
                      final friendUid = (friend['uid'] ?? '').toString();
                      final alreadyHere = _players.any(
                            (p) => (p["id"] ?? "").toString() == friendUid,
                      );

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.black.withOpacity(0.06),
                            child: const Icon(Icons.person),
                          ),
                          title: Text(
                            friend['username'],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle:
                          alreadyHere ? const Text('Already in lobby') : null,
                          trailing: FilledButton(
                            onPressed:
                            alreadyHere ? null : () => _sendGameInvite(friend),
                            child: Text(alreadyHere ? 'Here' : 'Invite'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    if (_players.isEmpty) return '-';
    final host = _players.first;
    return (host["name"] ?? '-').toString();
  }

  bool get _isHost {
    if (_youId == null || _players.isEmpty) return false;
    return (_players.first["id"] ?? '').toString() == _youId;
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
              _buildLobbyPill('BLACKJACK LOBBY'),
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
                : 'Everyone is ready to move into the table.',
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

  Widget _buildPlayerTile(Map<String, dynamic> p, int index) {
    final pid = (p["id"] ?? "").toString();
    final name = (p["name"] ?? pid).toString();
    final isYou = (_youId != null && pid == _youId);
    final isHost = index == 0;

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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Players in Lobby',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _loadingFriends ? null : _openInviteSheet,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Invite'),
              ),
            ],
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
                return _buildPlayerTile(p, i);
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
    final canEnter = _roomId != null && _players.isNotEmpty && currentUid.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Blackjack Lobby"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _loadingFriends ? null : _openInviteSheet,
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
              Color(0xFF14532D),
              Color(0xFF166534),
              Color(0xFF14532D),
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
                          builder: (_) => BlackjackTableScreen(
                            roomId: _roomId!,
                            playerId: currentUid,
                            playerName: _myName,
                          ),
                        ),
                      );
                    }
                        : null,
                    icon: const Icon(Icons.casino),
                    label: Text(
                      _players.length < 2 ? "Enter Table" : "Enter Table",
                    ),
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