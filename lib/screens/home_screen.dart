import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/primary_action_tile.dart';
import '../widgets/section_card.dart';
import '../widgets/info_stat_tile.dart';
import 'profile_screen.dart';
import 'matches_screen.dart';
import 'stats_screen.dart';
import 'blackjack_room_screen.dart';
import 'blackjack_screen.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';
import 'poker_room_screen.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    final notificationsQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('status', isEqualTo: 'pending');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: notificationsQuery.snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDoc.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          final coins = ((data?['coins'] ?? 0) as num).toInt();
          final username = (data?['username'] ?? 'Player').toString();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                '${_greeting()}, $username',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a mode, jump into a room, or review your progress.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: 'Overview',
                child: Row(
                  children: [
                    Expanded(
                      child: InfoStatTile(
                        label: 'Coin balance',
                        value: coins.toString(),
                        icon: Icons.monetization_on_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InfoStatTile(
                        label: 'Account',
                        value: username,
                        icon: Icons.verified_user_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Play',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.groups_rounded,
                title: 'Multiplayer Blackjack',
                subtitle: 'Create or join a room and play live with friends.',
                primary: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BlackjackRoomScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.casino_outlined,
                title: 'Singleplayer Blackjack',
                subtitle: 'Play a solo hand and build your stats.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BlackjackScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.table_bar_rounded,
                title: 'Multiplayer Poker',
                subtitle: 'Join a live Texas Hold’em room with real-time updates.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PokerRoomScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              Text(
                'Your Space',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.people_alt_outlined,
                title: 'Friends',
                subtitle: 'Manage your friends list and send requests.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FriendsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.history_rounded,
                title: 'Match History',
                subtitle: 'Review recent games, results, and room activity.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MatchesScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.bar_chart_rounded,
                title: 'Stats',
                subtitle: 'Track wins, streaks, coin performance, and more.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StatsScreen(),
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