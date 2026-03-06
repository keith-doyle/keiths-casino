import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/blackjack_ws_service.dart';
import 'blackjack_table_screen.dart';

class BlackjackLobbyScreen extends StatefulWidget {
  const BlackjackLobbyScreen({super.key});

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
    } catch (_) {

    }


    return uid.length >= 6 ? uid.substring(0, 6) : uid;
  }

  Future<void> _connectAndListen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        "test_${DateTime
            .now()
            .millisecondsSinceEpoch}";

    final username = await _fetchUsernameForUid(uid);
    if (!mounted) return;

    setState(() {
      _myName = username;
    });

    final roomId = "room1"; // testing
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("Blackjack Lobby"),
        centerTitle: true,
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
                        Text(
                            "You: $yourName", style: theme.textTheme.bodyLarge),
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
            Text(
              "Players",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_roomId == null || _players.isEmpty)
                    ? null
                    : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BlackjackTableScreen(
                            roomId: _roomId!,
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