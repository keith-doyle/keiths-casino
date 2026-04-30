import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'blackjack_lobby_screen.dart';

class BlackjackRoomScreen extends StatefulWidget {
  const BlackjackRoomScreen({super.key});

  @override
  State<BlackjackRoomScreen> createState() => _BlackjackRoomScreenState();
}

class _BlackjackRoomScreenState extends State<BlackjackRoomScreen> {
  final TextEditingController _roomCodeController = TextEditingController();

  static const String _baseHttp = 'http://16.170.162.140:8000';

  bool _busy = false;

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(
      6,
          (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<void> _createLobby() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to create a room.')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      String roomCode = _generateRoomCode();
      bool created = false;

      for (int i = 0; i < 5; i++) {
        final res = await http.post(
          Uri.parse('$_baseHttp/rooms/create'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'room_id': roomCode,
            'host_player_id': currentUid,
            'game': 'blackjack',
          }),
        );

        if (res.statusCode == 200) {
          created = true;
          break;
        }

        roomCode = _generateRoomCode();
      }

      if (!mounted) return;

      if (!created) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create room. Please try again.')),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BlackjackLobbyScreen(roomId: roomCode),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to contact server.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinLobby() async {
    final roomCode = _roomCodeController.text.trim().toUpperCase();

    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final res = await http.get(
        Uri.parse('$_baseHttp/rooms/$roomCode/exists'),
      );

      if (!mounted) return;

      if (res.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to check room. Try again.')),
        );
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final exists = data['exists'] == true;
      final roomGame = (data['game'] ?? '').toString().toLowerCase();

      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That room code does not exist.')),
        );
        return;
      }

      if (roomGame != 'blackjack') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That room code belongs to Poker.')),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BlackjackLobbyScreen(roomId: roomCode),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to contact server.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blackjack Rooms'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create Lobby',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a private blackjack lobby and share the room code with your friends.',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _createLobby,
                          icon: const Icon(Icons.add_circle_outline),
                          label: Text(_busy ? 'Working...' : 'Create Lobby'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Join Lobby',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter a room code to join a friend’s private blackjack lobby.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _roomCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Room Code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _joinLobby,
                          icon: const Icon(Icons.login),
                          label: Text(_busy ? 'Working...' : 'Join Lobby'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}