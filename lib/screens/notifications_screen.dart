import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'blackjack_lobby_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  static const String _baseHttp = 'http://16.170.162.140:8000';

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

  Future<void> _declineNotification(String notificationId, String successText) async {
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
        SnackBar(content: Text(successText)),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating notification: ${e.message ?? e.code}')),
      );
    }
  }

  Future<void> _joinGameInvite(String notificationId, String roomId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseHttp/rooms/${roomId.trim().toUpperCase()}/exists'),
      );

      if (!mounted) return;

      if (res.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to check room right now.')),
        );
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final exists = data['exists'] == true;

      if (!exists) {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .doc(notificationId)
            .update({'status': 'declined'});

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That room is no longer available.')),
        );
        return;
      }

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'status': 'accepted'});

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BlackjackLobbyScreen(roomId: roomId),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to join invite')),
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
                                onPressed: () => _declineNotification(
                                  doc.id,
                                  'Friend request declined',
                                ),
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

              if (type == 'game_invite') {
                final fromUsername = (data['fromUsername'] ?? 'Unknown').toString();
                final roomId = (data['roomId'] ?? '').toString();
                final game = (data['game'] ?? 'game').toString();

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$fromUsername invited you to a ${game[0].toUpperCase()}${game.substring(1)} room',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Room code: $roomId',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _joinGameInvite(doc.id, roomId),
                                child: const Text('Join'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _declineNotification(
                                  doc.id,
                                  'Game invite declined',
                                ),
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