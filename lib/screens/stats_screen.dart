import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/info_stat_tile.dart';
import '../widgets/section_card.dart';

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
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Performance',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Your blackjack stats update automatically as games finish.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: 'Blackjack Overview',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Games',
                            value: gamesPlayed.toString(),
                            icon: Icons.sports_esports,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Win rate',
                            value: '${winRate.toStringAsFixed(1)}%',
                            icon: Icons.bar_chart,
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
                            label: 'Losses',
                            value: losses.toString(),
                            icon: Icons.close_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Pushes',
                            value: pushes.toString(),
                            icon: Icons.horizontal_rule_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Economy',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Coins won',
                            value: coinsWon.toString(),
                            icon: Icons.trending_up_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Coins lost',
                            value: coinsLost.toString(),
                            icon: Icons.trending_down_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Net coins',
                            value: netCoins.toString(),
                            icon: Icons.monetization_on_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Highest bet',
                            value: highestBet.toString(),
                            icon: Icons.casino_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InfoStatTile(
                      label: 'Biggest win',
                      value: biggestWin.toString(),
                      icon: Icons.workspace_premium_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Mode Breakdown',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Singleplayer games',
                            value: singleplayerGames.toString(),
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Multiplayer games',
                            value: multiplayerGames.toString(),
                            icon: Icons.groups_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Singleplayer wins',
                            value: singleplayerWins.toString(),
                            icon: Icons.sports_score_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Multiplayer wins',
                            value: multiplayerWins.toString(),
                            icon: Icons.military_tech_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Streaks & Activity',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Current streak',
                            value: currentWinStreak.toString(),
                            icon: Icons.local_fire_department_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Best streak',
                            value: bestWinStreak.toString(),
                            icon: Icons.star_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InfoStatTile(
                      label: 'Last played',
                      value: _fmtDate(lastPlayedAt),
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}