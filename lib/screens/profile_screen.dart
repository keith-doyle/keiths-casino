// screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'matches_screen.dart';

class ProfileScreen extends StatelessWidget {
  ProfileScreen({super.key});

  String _fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return ts.toDate().toLocal().toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc =
    FirebaseFirestore.instance.collection('users').doc(uid);

    final recentMatchesQuery = userDoc
        .collection('matches')
        .orderBy('playedAt', descending: true)
        .limit(5);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDoc.snapshots(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = userSnap.data!.data()!;
          final username = data['username'];
          final email = data['email'];
          final created = data['createdAt'];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        child: Text(username[0].toUpperCase()),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(username,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600)),
                            Text(email),
                            const SizedBox(height: 8),
                            Text("Joined: ${_fmtDate(created)}"),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(
                    child: Text('Recent Matches',
                        style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MatchesScreen()));
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('See all'),
                  )
                ],
              ),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: recentMatchesQuery.snapshots(),
                builder: (context, matchSnap) {
                  if (!matchSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = matchSnap.data!.docs;

                  if (docs.isEmpty) {
                    return const Text("No matches yet.");
                  }

                  return Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, i) {
                        final m = docs[i].data();
                        final played = _fmtDate(m['playedAt']);

                        return ListTile(
                          leading: const Icon(Icons.sports_esports),
                          title: Text(m['gameType']),
                          subtitle: Text(played),
                          trailing: Text(m['result']),
                        );
                      },
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                      itemCount: docs.length,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
