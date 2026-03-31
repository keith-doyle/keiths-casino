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
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final friendIds = List<String>.from(userDoc.data()?['friends'] ?? []);

      final loaded = <Map<String, dynamic>>[];

      for (final fid in friendIds) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(fid).get();
        if (!doc.exists) continue;

        final data = doc.data() ?? {};
        loaded.add({
          'uid': fid,
          'username': (data['username'] ?? 'Unknown').toString(),
        });
      }

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
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(friend['username']),
                        trailing: FilledButton(
                          onPressed: () => _sendGameInvite(friend),
                          child: const Text('Invite'),
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

  @override
  void dispose() {
    _sub?.cancel();
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final yourPlayer = _players.firstWhere(
          (p) => p["id"] == _youId,
      orElse: () => {},
    );
    final yourName = (yourPlayer["name"] ?? _myName).toString();
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
                    const SizedBox(height: 4),
                    Text(
                      "Multiplayer Lobby",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You: $yourName",
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _status.startsWith("In room")
                            ? Colors.green[700]
                            : Colors.grey[700],
                      ),
                    ),
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
              child: ListView.builder(
                itemCount: _players.length,
                itemBuilder: (context, i) {
                  final p = _players[i];
                  final pid = (p["id"] ?? "").toString();
                  final name = (p["name"] ?? pid).toString();
                  final isYou = (_youId != null && pid == _youId);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.account_circle),
                      title: Text(name),
                      trailing: isYou
                          ? const Text(
                        "YOU",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      )
                          : null,
                    ),
                  );
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
                label: const Text("Enter Table"),
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