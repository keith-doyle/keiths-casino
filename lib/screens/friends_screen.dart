import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _controller = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _loading = false;
  List<Map<String, dynamic>> _friends = [];

  String get uid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final friendIds = List<String>.from(userDoc.data()?['friends'] ?? []);

      List<Map<String, dynamic>> loaded = [];

      for (final fid in friendIds) {
        final doc = await _firestore.collection('users').doc(fid).get();
        if (doc.exists) {
          final data = doc.data()!;
          loaded.add({
            'uid': fid,
            'username': (data['username'] ?? 'Unknown').toString(),
          });
        }
      }

      if (!mounted) return;
      setState(() => _friends = loaded);
    } catch (_) {
      _show('Error loading friends');
    }
  }

  Future<void> _sendFriendRequest() async {
    final rawUsername = _controller.text.trim();
    final usernameLower = rawUsername.toLowerCase();

    if (rawUsername.isEmpty) return;

    setState(() => _loading = true);

    try {
      final unameDoc =
      await _firestore.collection('usernames').doc(usernameLower).get();

      if (!unameDoc.exists) {
        _show("User not found");
        return;
      }

      final unameData = unameDoc.data()!;
      final targetUid = (unameData['uid'] ?? '').toString();

      if (targetUid.isEmpty) {
        _show("User not found");
        return;
      }

      if (targetUid == uid) {
        _show("You can't add yourself");
        return;
      }

      final myUserDoc = await _firestore.collection('users').doc(uid).get();
      final myData = myUserDoc.data() ?? {};
      final myUsername = (myData['username'] ?? '').toString();
      final currentFriends = List<String>.from(myData['friends'] ?? []);

      if (currentFriends.contains(targetUid)) {
        _show("That user is already in your friends list");
        return;
      }

      final notificationId = 'friend_request_$uid';
      final requestRef = _firestore
          .collection('users')
          .doc(targetUid)
          .collection('notifications')
          .doc(notificationId);

      final existing = await requestRef.get();

      if (existing.exists) {
        final existingData = existing.data() ?? {};
        final status = (existingData['status'] ?? '').toString();

        if (status == 'pending') {
          _show("You already have a pending friend request");
          return;
        }
      }

      await requestRef.set({
        'type': 'friend_request',
        'fromUid': uid,
        'fromUsername': myUsername,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _controller.clear();
      _show("Friend request sent!");
    } on FirebaseException catch (e) {
      debugPrint('FirebaseException send friend request: ${e.code} ${e.message}');
      _show("Error sending request: ${e.message ?? e.code}");
    } catch (e) {
      debugPrint('Generic send friend request error: $e');
      _show("Error sending request");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFriend(String friendUid) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'friends': FieldValue.arrayRemove([friendUid])
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(friendUid).set({
        'friends': FieldValue.arrayRemove([uid])
      }, SetOptions(merge: true));

      await _loadFriends();
      _show("Friend removed");
    } on FirebaseException catch (e) {
      _show("Error removing friend: ${e.message ?? e.code}");
    } catch (_) {
      _show("Error removing friend");
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Friends"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: "Add friend by username",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _loading ? null : _sendFriendRequest(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _loading ? null : _sendFriendRequest,
                  child: Text(_loading ? "..." : "Add"),
                )
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _friends.isEmpty
                  ? const Center(
                child: Text("No friends added yet."),
              )
                  : ListView.builder(
                itemCount: _friends.length,
                itemBuilder: (context, i) {
                  final f = _friends[i];

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(f['username']),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeFriend(f['uid']),
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}