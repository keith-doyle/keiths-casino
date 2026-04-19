import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/section_card.dart';
import 'chat_screen.dart';

class FriendProfileScreen extends StatelessWidget {
  final String friendUid;
  final String friendUsername;

  const FriendProfileScreen({
    super.key,
    required this.friendUid,
    required this.friendUsername,
  });

  String _fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return ts.toDate().toLocal().toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    final friendDoc =
    FirebaseFirestore.instance.collection('users').doc(friendUid);

    final statsDoc = friendDoc.collection('stats').doc('blackjack');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Profile'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: friendDoc.snapshots(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnap.data!.data();
          if (userData == null) {
            return const Center(
              child: Text('User profile not found.'),
            );
          }

          final username = (userData['username'] ?? friendUsername).toString();
          final email = (userData['email'] ?? '-').toString();
          final createdAt = userData['createdAt'];
          final coins = ((userData['coins'] ?? 0) as num).toInt();

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: statsDoc.snapshots(),
            builder: (context, statsSnap) {
              final stats = statsSnap.data?.data();

              final gamesPlayed = ((stats?['gamesPlayed'] ?? 0) as num).toInt();
              final wins = ((stats?['wins'] ?? 0) as num).toInt();
              final bestWinStreak =
              ((stats?['bestWinStreak'] ?? 0) as num).toInt();

              final winRate = gamesPlayed == 0
                  ? 0.0
                  : ((wins / gamesPlayed) * 100.0);

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.12),
                          child: Text(
                            username.isNotEmpty
                                ? username.substring(0, 1).toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Joined ${_fmtDate(createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Overview',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _infoTile(
                                context,
                                'Coins',
                                coins.toString(),
                                Icons.monetization_on_outlined,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _infoTile(
                                context,
                                'Games',
                                gamesPlayed.toString(),
                                Icons.sports_esports_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _infoTile(
                                context,
                                'Wins',
                                wins.toString(),
                                Icons.emoji_events_outlined,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _infoTile(
                                context,
                                'Win Rate',
                                '${winRate.toStringAsFixed(1)}%',
                                Icons.bar_chart_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _infoTile(
                          context,
                          'Best Streak',
                          bestWinStreak.toString(),
                          Icons.local_fire_department_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: myUid == friendUid
                        ? null
                        : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            friendUid: friendUid,
                            friendUsername: username,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Open Chat'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoTile(
      BuildContext context,
      String label,
      String value,
      IconData icon,
      ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.035),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}