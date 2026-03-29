import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  double _winRate(int wins, int gamesPlayed) {
    if (gamesPlayed == 0) return 0;
    return (wins / gamesPlayed) * 100.0;
  }

  String _fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return ts.toDate().toLocal().toString().split('.').first;
  }

  Widget _statTile(String label, String value, {IconData? icon}) {
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
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final statsDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('blackjack');

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: statsDoc.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();

          final gamesPlayed = ((data?['gamesPlayed'] ?? 0) as num).toInt();
          final wins = ((data?['wins'] ?? 0) as num).toInt();
          final losses = ((data?['losses'] ?? 0) as num).toInt();
          final pushes = ((data?['pushes'] ?? 0) as num).toInt();

          final singleplayerGames =
          ((data?['singleplayerGames'] ?? 0) as num).toInt();
          final multiplayerGames =
          ((data?['multiplayerGames'] ?? 0) as num).toInt();
          final singleplayerWins =
          ((data?['singleplayerWins'] ?? 0) as num).toInt();
          final multiplayerWins =
          ((data?['multiplayerWins'] ?? 0) as num).toInt();

          final coinsWon = ((data?['coinsWon'] ?? 0) as num).toInt();
          final coinsLost = ((data?['coinsLost'] ?? 0) as num).toInt();
          final netCoins = ((data?['netCoins'] ?? 0) as num).toInt();
          final highestBet = ((data?['highestBet'] ?? 0) as num).toInt();
          final biggestWin = ((data?['biggestWin'] ?? 0) as num).toInt();

          final currentWinStreak =
          ((data?['currentWinStreak'] ?? 0) as num).toInt();
          final bestWinStreak =
          ((data?['bestWinStreak'] ?? 0) as num).toInt();

          final lastPlayedAt = data?['lastPlayedAt'];

          final winRate = _winRate(wins, gamesPlayed);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionCard(
                title: 'Blackjack Overview',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Games',
                          gamesPlayed.toString(),
                          icon: Icons.sports_esports,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Win rate',
                          '${winRate.toStringAsFixed(1)}%',
                          icon: Icons.bar_chart,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Wins',
                          wins.toString(),
                          icon: Icons.emoji_events,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Losses',
                          losses.toString(),
                          icon: Icons.close,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Pushes',
                          pushes.toString(),
                          icon: Icons.horizontal_rule,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Economy',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Coins won',
                          coinsWon.toString(),
                          icon: Icons.trending_up,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Coins lost',
                          coinsLost.toString(),
                          icon: Icons.trending_down,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Net coins',
                          netCoins.toString(),
                          icon: Icons.monetization_on,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Highest bet',
                          highestBet.toString(),
                          icon: Icons.casino,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statTile(
                    'Biggest win',
                    biggestWin.toString(),
                    icon: Icons.workspace_premium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Mode Breakdown',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Singleplayer games',
                          singleplayerGames.toString(),
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Multiplayer games',
                          multiplayerGames.toString(),
                          icon: Icons.group,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Singleplayer wins',
                          singleplayerWins.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Multiplayer wins',
                          multiplayerWins.toString(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Streaks & Activity',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          'Current streak',
                          currentWinStreak.toString(),
                          icon: Icons.local_fire_department,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          'Best streak',
                          bestWinStreak.toString(),
                          icon: Icons.star,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statTile(
                    'Last played',
                    _fmtDate(lastPlayedAt),
                    icon: Icons.schedule,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'These stats update automatically when a blackjack hand ends.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}