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

      loaded.sort((a, b) => a['username']
          .toString()
          .toLowerCase()
          .compareTo(b['username'].toString().toLowerCase()));

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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final friend = _friends[i];
                      final friendUid = (friend['uid'] ?? '').toString();
                      final alreadyHere =
                      _players.any((p) => (p["id"] ?? "").toString() == friendUid);

                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(friend['username']),
                        subtitle:
                        alreadyHere ? const Text('Already in lobby') : null,
                        trailing: FilledButton(
                          onPressed:
                          alreadyHere ? null : () => _sendGameInvite(friend),
                          child: Text(alreadyHere ? 'Here' : 'Invite'),
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

    _sub = _ws.stream?.listen((event) {
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
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _status = "WS error: $e";
        _busy = false;
      });
    }, onDone: () {
      if (!mounted) return;
      setState(() {
        _status = "Disconnected";
        _busy = false;
      });
    });
  }

  String _compactStatusText() {
    if (_busy) return 'Joining lobby...';
    if (_players.length < 2) return 'Waiting for more players';
    return 'Ready to enter table';
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

  Widget _buildInfoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _compactStatusColor().withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _compactStatusColor().withOpacity(0.55),
        ),
      ),
      child: Column(
        children: [
          Text(
            _compactStatusText(),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: _compactStatusColor(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _players.length < 2
                ? 'Minimum 2 players are needed before starting.'
                : 'Everyone is ready to move into the blackjack table.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.account_circle),
        title: Text(name),
        subtitle: Text(isHost ? 'Host' : 'Player'),
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (isHost)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                "YOU",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
          ],
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
    final theme = Theme.of(context);
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Room ${_roomId ?? "-"}",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildInfoPill('Players: ${_players.length}'),
                        _buildInfoPill(
                          _isHost ? 'Host: You' : 'Host: ${_hostName()}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStatusCard(theme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  "Players",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _loadingFriends ? null : _openInviteSheet,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Invite'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _players.isEmpty
                  ? Center(
                child: Text(
                  _busy ? 'Joining lobby...' : 'No players in lobby',
                  style: theme.textTheme.bodyLarge,
                ),
              )
                  : ListView.builder(
                itemCount: _players.length,
                itemBuilder: (context, i) {
                  final p = _players[i];
                  return _buildPlayerTile(p, i);
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_roomId == null ||
                    _players.isEmpty ||
                    currentUid.isEmpty)
                    ? null
                    : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlackjackTableScreen(
                        roomId: _roomId!,
                        playerId: currentUid,
                        playerName: _myName,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.casino),
                label: Text(
                  _players.length < 2 ? "Enter Table" : "Enter Table",
                ),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text("Working..."),
              ),
          ],
        ),
      ),
    );
  }
}