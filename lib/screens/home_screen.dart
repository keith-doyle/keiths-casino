// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'profile_screen.dart';
import 'blackjack_screen.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  Future<void> _addTestMatch() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final matches = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('matches');

    await matches.add({
      'gameType': 'Blackjack',
      'result': 'Win',
      'playedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProfileScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Test Match'),
              onPressed: _addTestMatch,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.casino),
              label: const Text('Play Blackjack'),
              onPressed: () {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BlackjackScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
