import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/info_stat_tile.dart';
import '../widgets/section_card.dart';
import '../widgets/empty_state_widget.dart';
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

  double _winRate(int wins, int gamesPlayed) {
    if (gamesPlayed == 0) return 0;
    return (wins / gamesPlayed) * 100.0;
  }

  Color _resultColor(String result) {
    switch (result) {
      case 'Win':
        return Colors.green.shade700;
      case 'Loss':
        return Colors.red.shade700;
      case 'Push':
        return Colors.orange.shade700;
      default:
        return Colors.black87;
    }
  }

  int _intVal(Map<String, dynamic>? data, String key) {
    return ((data?[key] ?? 0) as num).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    final friendDoc =
    FirebaseFirestore.instance.collection('users').doc(friendUid);
    final blackjackStatsDoc = friendDoc.collection('stats').doc('blackjack');
    final pokerStatsDoc = friendDoc.collection('stats').doc('poker');
    final recentMatchesQuery = friendDoc
        .collection('matches')
        .orderBy('playedAt', descending: true)
        .limit(5);

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
            stream: blackjackStatsDoc.snapshots(),
            builder: (context, blackjackSnap) {
              final blackjack = blackjackSnap.data?.data();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: pokerStatsDoc.snapshots(),
                builder: (context, pokerSnap) {
                  final poker = pokerSnap.data?.data();

                  final blackjackGames = _intVal(blackjack, 'gamesPlayed');
                  final blackjackWins = _intVal(blackjack, 'wins');
                  final blackjackBestStreak = _intVal(blackjack, 'bestWinStreak');
                  final blackjackHighestBet = _intVal(blackjack, 'highestBet');

                  final pokerGames = _intVal(poker, 'gamesPlayed');
                  final pokerWins = _intVal(poker, 'wins');
                  final pokerBestStreak = _intVal(poker, 'bestWinStreak');
                  final pokerHighestPot = _intVal(poker, 'highestPotSeen');

                  final gamesPlayed = blackjackGames + pokerGames;
                  final wins = blackjackWins + pokerWins;
                  final bestWinStreak =
                  math.max(blackjackBestStreak, pokerBestStreak);
                  final highestHighlight =
                  math.max(blackjackHighestBet, pokerHighestPot);
                  final winRate = _winRate(wins, gamesPlayed);

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
                                  child: InfoStatTile(
                                    label: 'Coins',
                                    value: coins.toString(),
                                    icon: Icons.monetization_on_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Games',
                                    value: gamesPlayed.toString(),
                                    icon: Icons.sports_esports_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Wins',
                                    value: wins.toString(),
                                    icon: Icons.emoji_events_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Win Rate',
                                    value: '${winRate.toStringAsFixed(1)}%',
                                    icon: Icons.bar_chart_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Best Streak',
                                    value: bestWinStreak.toString(),
                                    icon: Icons.local_fire_department_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Highest stake',
                                    value: highestHighlight.toString(),
                                    icon: Icons.casino_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SectionCard(
                        title: 'Recent Matches',
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: recentMatchesQuery.snapshots(),
                          builder: (context, matchSnap) {
                            if (matchSnap.hasError) {
                              return const EmptyStateWidget(
                                icon: Icons.lock_outline_rounded,
                                title: 'Recent matches unavailable',
                                subtitle: 'This usually means Firestore rules still block reading friend match history.',
                              );
                            }

                            if (!matchSnap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            final docs = matchSnap.data!.docs;

                            if (docs.isEmpty) {
                              return const EmptyStateWidget(
                                icon: Icons.history_toggle_off_rounded,
                                title: 'No matches yet',
                                subtitle: 'This player has no saved matches yet.',
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const Divider(height: 20),
                              itemBuilder: (context, i) {
                                final m = docs[i].data();
                                final played = _fmtDate(m['playedAt']);
                                final gameType =
                                (m['gameType'] ?? 'Unknown').toString();
                                final result = (m['result'] ?? '-').toString();
                                final coinDelta =
                                ((m['coinDelta'] ?? 0) as num).toInt();

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.black.withOpacity(0.05),
                                    child: Icon(
                                      gameType.toLowerCase().contains('poker')
                                          ? Icons.table_bar_rounded
                                          : Icons.sports_esports,
                                    ),
                                  ),
                                  title: Text(
                                    gameType,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(played),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        result,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _resultColor(result),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        coinDelta > 0
                                            ? '+$coinDelta'
                                            : coinDelta.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: coinDelta > 0
                                              ? Colors.green.shade700
                                              : (coinDelta < 0
                                              ? Colors.red.shade700
                                              : Colors.black54),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
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
          );
        },
      ),
    );
  }
}