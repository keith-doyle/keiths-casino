import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/info_stat_tile.dart';
import '../widgets/primary_action_tile.dart';
import '../widgets/section_card.dart';
import 'blackjack_room_screen.dart';
import 'blackjack_screen.dart';
import 'friends_screen.dart';
import 'matches_screen.dart';
import 'notifications_screen.dart';
import 'poker_room_screen.dart';
import 'profile_screen.dart';
import 'singleplayer_poker_screen.dart';
import 'stats_screen.dart';
import 'tutorial_poker_screen.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
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
                    tooltip: 'Notifications',
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
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
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
                'Choose a multiplayer table, a solo mode, or a guided tutorial.',
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

              const SizedBox(height: 24),
              _sectionLabel(context, 'Blackjack'),

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
                subtitle: 'Play solo, use your coin balance, and build your stats.',
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
                icon: Icons.school_outlined,
                title: 'Tutorial Blackjack',
                subtitle: 'Learn totals, dealer logic, hit, and stand using practice coins.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BlackjackScreen(
                        tutorialMode: true,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
              _sectionLabel(context, 'Poker'),

              PrimaryActionTile(
                icon: Icons.groups_rounded,
                title: 'Multiplayer Poker',
                subtitle: 'Join a live poker room with friends.',
                primary: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PokerRoomScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.person_outline_rounded,
                title: 'Singleplayer Poker',
                subtitle: 'Play a simplified solo poker mode and record stats and matches.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SingleplayerPokerScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              PrimaryActionTile(
                icon: Icons.menu_book_rounded,
                title: 'Tutorial Poker',
                subtitle: 'Learn phases, actions, and table flow while playing with practice chips.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TutorialPokerScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
              _sectionLabel(context, 'Your Space'),

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
                subtitle: 'Track wins, streaks, coin performance, and mode splits.',
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