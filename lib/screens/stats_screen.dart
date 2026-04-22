import 'dart:math' as math;

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

  int _intVal(Map<String, dynamic>? data, String key) {
    return ((data?[key] ?? 0) as num).toInt();
  }

  Widget _buildTopPill(String text, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSummaryHero({
    required int totalGames,
    required int totalWins,
    required double totalWinRate,
    required int totalNetCoins,
  }) {
    final netColor = totalNetCoins > 0
        ? Colors.green.shade300
        : totalNetCoins < 0
        ? Colors.red.shade300
        : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildTopPill('PERFORMANCE'),
              _buildTopPill('Games $totalGames'),
              _buildTopPill('Wins $totalWins'),
              _buildTopPill(
                'Net ${totalNetCoins > 0 ? '+$totalNetCoins' : totalNetCoins}',
                textColor: netColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${totalWinRate.toStringAsFixed(1)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Overall Win Rate',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSpacing() => const SizedBox(height: 16);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final blackjackStatsDoc = userRef.collection('stats').doc('blackjack');
    final pokerStatsDoc = userRef.collection('stats').doc('poker');

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFF1F5F9),
              Color(0xFFE2E8F0),
            ],
          ),
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: blackjackStatsDoc.snapshots(),
          builder: (context, blackjackSnap) {
            if (!blackjackSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: pokerStatsDoc.snapshots(),
              builder: (context, pokerSnap) {
                if (!pokerSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final blackjack = blackjackSnap.data!.data();
                final poker = pokerSnap.data!.data();

                final bjGames = _intVal(blackjack, 'gamesPlayed');
                final bjWins = _intVal(blackjack, 'wins');
                final bjLosses = _intVal(blackjack, 'losses');
                final bjPushes = _intVal(blackjack, 'pushes');
                final bjSingleplayerGames =
                _intVal(blackjack, 'singleplayerGames');
                final bjMultiplayerGames =
                _intVal(blackjack, 'multiplayerGames');
                final bjSingleplayerWins =
                _intVal(blackjack, 'singleplayerWins');
                final bjMultiplayerWins =
                _intVal(blackjack, 'multiplayerWins');
                final bjCoinsWon = _intVal(blackjack, 'coinsWon');
                final bjCoinsLost = _intVal(blackjack, 'coinsLost');
                final bjNetCoins = _intVal(blackjack, 'netCoins');
                final bjHighestBet = _intVal(blackjack, 'highestBet');
                final bjBiggestWin = _intVal(blackjack, 'biggestWin');
                final bjCurrentWinStreak =
                _intVal(blackjack, 'currentWinStreak');
                final bjBestWinStreak = _intVal(blackjack, 'bestWinStreak');
                final bjLastPlayedAt = blackjack?['lastPlayedAt'];
                final bjWinRate = _winRate(bjWins, bjGames);

                final pokerGames = _intVal(poker, 'gamesPlayed');
                final pokerWins = _intVal(poker, 'wins');
                final pokerLosses = _intVal(poker, 'losses');
                final pokerCoinsWon = _intVal(poker, 'coinsWon');
                final pokerCoinsLost = _intVal(poker, 'coinsLost');
                final pokerNetCoins = _intVal(poker, 'netCoins');
                final pokerCurrentWinStreak =
                _intVal(poker, 'currentWinStreak');
                final pokerBestWinStreak = _intVal(poker, 'bestWinStreak');
                final pokerHighestPotSeen = _intVal(poker, 'highestPotSeen');
                final pokerSingleplayerGames =
                _intVal(poker, 'singleplayerGames');
                final pokerMultiplayerGames =
                _intVal(poker, 'multiplayerGames');
                final pokerSingleplayerWins =
                _intVal(poker, 'singleplayerWins');
                final pokerMultiplayerWins =
                _intVal(poker, 'multiplayerWins');
                final pokerLastPlayedAt = poker?['lastPlayedAt'];
                final pokerWinRate = _winRate(pokerWins, pokerGames);

                final totalGames = bjGames + pokerGames;
                final totalWins = bjWins + pokerWins;
                final totalLosses = bjLosses + pokerLosses;
                final totalNetCoins = bjNetCoins + pokerNetCoins;
                final totalWinRate = _winRate(totalWins, totalGames);

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildSummaryHero(
                      totalGames: totalGames,
                      totalWins: totalWins,
                      totalWinRate: totalWinRate,
                      totalNetCoins: totalNetCoins,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your blackjack and poker stats update automatically as games finish.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Overall Overview',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Total games',
                                  value: totalGames.toString(),
                                  icon: Icons.sports_esports,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Overall win rate',
                                  value: '${totalWinRate.toStringAsFixed(1)}%',
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
                                  label: 'Total wins',
                                  value: totalWins.toString(),
                                  icon: Icons.emoji_events_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Total losses',
                                  value: totalLosses.toString(),
                                  icon: Icons.close_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InfoStatTile(
                            label: 'Net coins',
                            value: totalNetCoins.toString(),
                            icon: Icons.monetization_on_outlined,
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Blackjack Overview',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Games',
                                  value: bjGames.toString(),
                                  icon: Icons.sports_esports,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Win rate',
                                  value: '${bjWinRate.toStringAsFixed(1)}%',
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
                                  value: bjWins.toString(),
                                  icon: Icons.emoji_events_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Losses',
                                  value: bjLosses.toString(),
                                  icon: Icons.close_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Pushes',
                                  value: bjPushes.toString(),
                                  icon: Icons.horizontal_rule_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Blackjack Economy',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Coins won',
                                  value: bjCoinsWon.toString(),
                                  icon: Icons.trending_up_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Coins lost',
                                  value: bjCoinsLost.toString(),
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
                                  value: bjNetCoins.toString(),
                                  icon: Icons.monetization_on_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Highest bet',
                                  value: bjHighestBet.toString(),
                                  icon: Icons.casino_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InfoStatTile(
                            label: 'Biggest win',
                            value: bjBiggestWin.toString(),
                            icon: Icons.workspace_premium_outlined,
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Blackjack Modes',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Singleplayer games',
                                  value: bjSingleplayerGames.toString(),
                                  icon: Icons.person_outline_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Multiplayer games',
                                  value: bjMultiplayerGames.toString(),
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
                                  value: bjSingleplayerWins.toString(),
                                  icon: Icons.sports_score_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Multiplayer wins',
                                  value: bjMultiplayerWins.toString(),
                                  icon: Icons.military_tech_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Blackjack Streaks',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Current streak',
                                  value: bjCurrentWinStreak.toString(),
                                  icon: Icons.local_fire_department_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Best streak',
                                  value: bjBestWinStreak.toString(),
                                  icon: Icons.star_outline_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InfoStatTile(
                            label: 'Last played',
                            value: _fmtDate(bjLastPlayedAt),
                            icon: Icons.schedule_rounded,
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Poker Overview',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Games',
                                  value: pokerGames.toString(),
                                  icon: Icons.table_bar_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Win rate',
                                  value: '${pokerWinRate.toStringAsFixed(1)}%',
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
                                  value: pokerWins.toString(),
                                  icon: Icons.emoji_events_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Losses',
                                  value: pokerLosses.toString(),
                                  icon: Icons.close_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Poker Economy',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Coins won',
                                  value: pokerCoinsWon.toString(),
                                  icon: Icons.trending_up_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Coins lost',
                                  value: pokerCoinsLost.toString(),
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
                                  value: pokerNetCoins.toString(),
                                  icon: Icons.monetization_on_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Highest pot',
                                  value: pokerHighestPotSeen.toString(),
                                  icon: Icons.account_balance_wallet_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Poker Modes',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Singleplayer games',
                                  value: pokerSingleplayerGames.toString(),
                                  icon: Icons.person_outline_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Multiplayer games',
                                  value: pokerMultiplayerGames.toString(),
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
                                  value: pokerSingleplayerWins.toString(),
                                  icon: Icons.sports_score_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Multiplayer wins',
                                  value: pokerMultiplayerWins.toString(),
                                  icon: Icons.military_tech_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildSectionSpacing(),

                    SectionCard(
                      title: 'Poker Streaks',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Current streak',
                                  value: pokerCurrentWinStreak.toString(),
                                  icon: Icons.local_fire_department_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InfoStatTile(
                                  label: 'Best streak',
                                  value: pokerBestWinStreak.toString(),
                                  icon: Icons.star_outline_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InfoStatTile(
                            label: 'Last played',
                            value: _fmtDate(pokerLastPlayedAt),
                            icon: Icons.schedule_rounded,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}