import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_screen.dart';
import 'matches_screen.dart';
import 'stats_screen.dart';
import 'blackjack_room_screen.dart';
import 'blackjack_screen.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen()),
              );
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
              icon: const Icon(Icons.group),
              label: const Text('Play Blackjack'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BlackjackRoomScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.casino),
              label: const Text('Blackjack'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BlackjackScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('My Matches'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MatchesScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.bar_chart),
              label: const Text('Stats'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}