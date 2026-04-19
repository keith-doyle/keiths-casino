import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_app/screens/friends_profile_screen.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/section_card.dart';

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

      final loaded = <Map<String, dynamic>>[];

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

      await requestRef.set({
        'type': 'friend_request',
        'fromUid': uid,
        'fromUsername': myUsername,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _controller.clear();
      _show("Friend request sent!");
    } on FirebaseException catch (e) {
      _show("Error sending request: ${e.message ?? e.code}");
    } catch (_) {
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(
            title: 'Add a Friend',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      hintText: "Search by username",
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onSubmitted: (_) => _loading ? null : _sendFriendRequest(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _loading ? null : _sendFriendRequest,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(90, 54),
                  ),
                  child: Text(_loading ? "..." : "Add"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
      SectionCard(
        title: 'Your Friends',
        child: _friends.isEmpty
            ? const EmptyStateWidget(
          icon: Icons.people_outline_rounded,
          title: 'No friends added yet',
          subtitle:
          'Send a friend request to start building your network.',
        )
            : ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _friends.length,
          separatorBuilder: (_, __) => const Divider(height: 20),
          itemBuilder: (context, i) {
            final f = _friends[i];

            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendProfileScreen(
                      friendUid: f['uid'],
                      friendUsername: f['username'],
                    ),
                  ),
                );
              },
              leading: CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.12),
                child: Text(
                  f['username']
                      .toString()
                      .substring(0, 1)
                      .toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              title: Text(
                f['username'],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Friend'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.person_outline_rounded),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FriendProfileScreen(
                            friendUid: f['uid'],
                            friendUsername: f['username'],
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    onPressed: () => _removeFriend(f['uid']),
                  ),
                ],
              ),
            );
          },
        ),
      ),
        ],
      ),
    );
  }
}