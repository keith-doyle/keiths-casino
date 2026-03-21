import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String get uid => _auth.currentUser!.uid;

  Future<void> _acceptFriendRequest(
      String notificationId,
      String fromUid,
      ) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'friends': FieldValue.arrayUnion([fromUid])
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(fromUid).set({
        'friends': FieldValue.arrayUnion([uid])
      }, SetOptions(merge: true));

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId)
          .update({
        'status': 'accepted',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request accepted')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accepting request: ${e.message ?? e.code}')),
      );
    }
  }

  Future<void> _declineFriendRequest(String notificationId) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId)
          .update({
        'status': 'declined',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request declined')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error declining request: ${e.message ?? e.code}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsQuery = _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('status', isEqualTo: 'pending');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: notificationsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading notifications:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];

          docs.sort((a, b) {
            final aTs = a.data()['createdAt'];
            final bTs = b.data()['createdAt'];

            if (aTs is Timestamp && bTs is Timestamp) {
              return bTs.compareTo(aTs);
            }
            return 0;
          });

          if (docs.isEmpty) {
            return const Center(
              child: Text('No pending notifications.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();

              final type = (data['type'] ?? '').toString();

              if (type == 'friend_request') {
                final fromUsername = (data['fromUsername'] ?? 'Unknown').toString();
                final fromUid = (data['fromUid'] ?? '').toString();

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$fromUsername sent you a friend request',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    _acceptFriendRequest(doc.id, fromUid),
                                child: const Text('Accept'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _declineFriendRequest(doc.id),
                                child: const Text('Decline'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}