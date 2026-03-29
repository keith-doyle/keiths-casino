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

  double _winRate(int wins, int gamesPlayed) {
    if (gamesPlayed == 0) return 0;
    return (wins / gamesPlayed) * 100.0;
  }

  Widget _summaryTile(String label, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    final statsDoc = userDoc.collection('stats').doc('blackjack');

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
            stream: statsDoc.snapshots(),
            builder: (context, statsSnap) {
              final stats = statsSnap.data?.data();

              final gamesPlayed = ((stats?['gamesPlayed'] ?? 0) as num).toInt();
              final wins = ((stats?['wins'] ?? 0) as num).toInt();
              final bestWinStreak =
              ((stats?['bestWinStreak'] ?? 0) as num).toInt();
              final highestBet = ((stats?['highestBet'] ?? 0) as num).toInt();

              final winRate = _winRate(wins, gamesPlayed);

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
                            child: Text(
                              username.isNotEmpty ? username[0].toUpperCase() : '?',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  username,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Overview',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _summaryTile(
                                  'Coins',
                                  coins.toString(),
                                  icon: Icons.monetization_on,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _summaryTile(
                                  'Games',
                                  gamesPlayed.toString(),
                                  icon: Icons.sports_esports,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _summaryTile(
                                  'Win rate',
                                  '${winRate.toStringAsFixed(1)}%',
                                  icon: Icons.bar_chart,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _summaryTile(
                                  'Best streak',
                                  bestWinStreak.toString(),
                                  icon: Icons.local_fire_department,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _summaryTile(
                            'Highest bet',
                            highestBet.toString(),
                            icon: Icons.casino,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recent Matches',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MatchesScreen()),
                          );
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
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "No matches yet.",
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        );
                      }

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, i) {
                            final m = docs[i].data();
                            final played = _fmtDate(m['playedAt']);

                            final gameType =
                            (m['gameType'] ?? 'Blackjack').toString();
                            final result = (m['result'] ?? '-').toString();
                            final mode = (m['mode'] ?? '').toString();
                            final bet = ((m['bet'] ?? 0) as num).toInt();
                            final coinDelta =
                            ((m['coinDelta'] ?? 0) as num).toInt();

                            return ListTile(
                              leading: const Icon(Icons.sports_esports),
                              title: Text(gameType),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(played),
                                  const SizedBox(height: 2),
                                  Text(
                                    mode.isEmpty
                                        ? 'Bet: $bet'
                                        : '${mode[0].toUpperCase()}${mode.substring(1)} • Bet: $bet',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
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
                                      fontWeight: FontWeight.w600,
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
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemCount: docs.length,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}