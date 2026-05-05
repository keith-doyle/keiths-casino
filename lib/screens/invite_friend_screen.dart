import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class InviteFriendScreen extends StatefulWidget {
  final String roomId;
  final String game;
  final String fromUsername;
  final List<Map<String, dynamic>> players;

  const InviteFriendScreen({
    super.key,
    required this.roomId,
    required this.game,
    required this.fromUsername,
    required this.players,
  });

  @override
  State<InviteFriendScreen> createState() => _InviteFriendScreenState();
}

class _InviteFriendScreenState extends State<InviteFriendScreen> {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }
//Reads users friends array, fetches each friend document and displays invite targets
  Future<void> _loadFriends() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      final rawFriends = userDoc.data()?['friends'];

      final friendIds = rawFriends is List
          ? rawFriends
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList()
          : <String>[];

      final loaded = <Map<String, dynamic>>[];

      for (final fid in friendIds) {
        final friendDoc =
        await FirebaseFirestore.instance.collection('users').doc(fid).get();

        final data = friendDoc.data() ?? {};
        final fallback = fid.length >= 6 ? fid.substring(0, 6) : fid;

        loaded.add({
          'uid': fid,
          'username': (data['username'] ?? data['usernameLower'] ?? fallback)
              .toString(),
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
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }
//Writes game invite notification to friend
  Future<void> _sendInvite(Map<String, dynamic> friend) async {
    if (_sending) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final friendUid = (friend['uid'] ?? '').toString();
    final friendUsername = (friend['username'] ?? 'Friend').toString();

    if (friendUid.isEmpty) return;

    setState(() => _sending = true);

    try {
      final notificationId =
      //Creates game invite notification id, game room id user who sent invite
          'game_invite_${currentUid}_${widget.roomId}_${widget.game}';
//writes fields for notifications subcollection, makes invites actionable with fields
      await FirebaseFirestore.instance
          .collection('users')
          .doc(friendUid)
          .collection('notifications')
          .doc(notificationId)
          .set({
        'type': 'game_invite',
        'fromUid': currentUid,
        'fromUsername': widget.fromUsername,
        'toUid': friendUid,
        'toUsername': friendUsername,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'roomId': widget.roomId,
        'game': widget.game,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite sent to $friendUsername')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      setState(() => _sending = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite failed: $e')),
      );
    }
  }

  Widget _friendTile(Map<String, dynamic> friend) {
    final friendUid = (friend['uid'] ?? '').toString();
    final friendName = (friend['username'] ?? 'Friend').toString();

    final alreadyHere = widget.players.any(
          (p) => (p['id'] ?? '').toString() == friendUid,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE5E7EB),
            child: Icon(Icons.person, color: Colors.black87),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              friendName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          GestureDetector(
            onTap: alreadyHere || _sending ? null : () => _sendInvite(friend),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: alreadyHere || _sending
                    ? Colors.grey
                    : const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                alreadyHere
                    ? 'Here'
                    : _sending
                    ? 'Sending'
                    : 'Invite',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load friends:\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_friends.isEmpty) {
      return const Center(
        child: Text(
          'No friends available to invite.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _friends.take(8).map(_friendTile).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Invite a Friend'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _content(),
      ),
    );
  }
}