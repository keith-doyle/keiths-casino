import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MatchesScreen extends StatelessWidget {
  MatchesScreen({super.key});

  String _fmtPlayedAt(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return ts.toDate().toLocal().toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('matches')
        .orderBy('playedAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('My Matches')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No matches yet."));
          }

          return ListView.separated(
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final played = _fmtPlayedAt(data['playedAt']);

              final gameType = (data['gameType'] ?? 'Unknown').toString();
              final result = (data['result'] ?? '-').toString();

              return ListTile(
                leading: const Icon(Icons.sports_esports),
                title: Text('$gameType • $result'),
                subtitle: Text(played),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: docs.length,
          );
        },
      ),
    );
  }
}
