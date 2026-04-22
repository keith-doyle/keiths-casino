import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/info_stat_tile.dart';
import '../widgets/section_card.dart';
import '../widgets/empty_state_widget.dart';
import 'matches_screen.dart';

class ProfileScreen extends StatelessWidget {
  ProfileScreen({super.key});

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

  Color _resultSoftBg(String result) {
    switch (result) {
      case 'Win':
        return Colors.green.withOpacity(0.10);
      case 'Loss':
        return Colors.red.withOpacity(0.10);
      case 'Push':
        return Colors.orange.withOpacity(0.10);
      default:
        return Colors.black.withOpacity(0.05);
    }
  }

  int _intVal(Map<String, dynamic>? data, String key) {
    return ((data?[key] ?? 0) as num).toInt();
  }

  IconData _matchIcon(String gameType) {
    return gameType.toLowerCase().contains('poker')
        ? Icons.table_bar_rounded
        : Icons.casino_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    final blackjackStatsDoc = userDoc.collection('stats').doc('blackjack');
    final pokerStatsDoc = userDoc.collection('stats').doc('poker');

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
          final username = (data['username'] ?? '-').toString();
          final email = (data['email'] ?? '-').toString();
          final created = data['createdAt'];
          final coins = ((data['coins'] ?? 0) as num).toInt();

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
                  final blackjackBestStreak =
                  _intVal(blackjack, 'bestWinStreak');
                  final blackjackHighestBet =
                  _intVal(blackjack, 'highestBet');

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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      Text(
                        'Player Profile',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Review your account, progress, and recent match activity.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),

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
                                  .withOpacity(0.14),
                              child: Text(
                                username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color:
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username,
                                    style:
                                    Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    style:
                                    Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Joined ${_fmtDate(created)}',
                                    style:
                                    Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      SectionCard(
                        title: 'Quick Overview',
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
                                    icon: Icons.sports_esports,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Win rate',
                                    value:
                                    '${winRate.toStringAsFixed(1)}%',
                                    icon: Icons.bar_chart_rounded,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InfoStatTile(
                                    label: 'Best streak',
                                    value: bestWinStreak.toString(),
                                    icon: Icons.local_fire_department_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            InfoStatTile(
                              label: 'Highest stake',
                              value: highestHighlight.toString(),
                              icon: Icons.casino_outlined,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      SectionCard(
                        title: 'Recent Matches',
                        trailing: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MatchesScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('See all'),
                        ),
                        child:
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: recentMatchesQuery.snapshots(),
                          builder: (context, matchSnap) {
                            if (!matchSnap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final docs = matchSnap.data!.docs;

                            if (docs.isEmpty) {
                              return const EmptyStateWidget(
                                icon: Icons.history_toggle_off_rounded,
                                title: 'No matches yet',
                                subtitle:
                                'Play a game to start building your match history.',
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics:
                              const NeverScrollableScrollPhysics(),
                              itemBuilder: (context, i) {
                                final m = docs[i].data();
                                final played = _fmtDate(m['playedAt']);
                                final gameType =
                                (m['gameType'] ?? 'Unknown').toString();
                                final result =
                                (m['result'] ?? '-').toString();
                                final mode = (m['mode'] ?? '').toString();
                                final coinDelta =
                                ((m['coinDelta'] ?? 0) as num).toInt();

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor:
                                    Colors.black.withOpacity(0.05),
                                    child: Icon(_matchIcon(gameType)),
                                  ),
                                  title: Text(
                                    gameType,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(played),
                                      const SizedBox(height: 4),
                                      if (mode.isNotEmpty)
                                        Text(
                                          mode[0].toUpperCase() +
                                              mode.substring(1),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _resultSoftBg(result),
                                          borderRadius:
                                          BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          result,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: _resultColor(result),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        coinDelta > 0
                                            ? '+$coinDelta'
                                            : coinDelta.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
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
                              separatorBuilder: (_, __) =>
                              const Divider(height: 20),
                              itemCount: docs.length,
                            );
                          },
                        ),
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