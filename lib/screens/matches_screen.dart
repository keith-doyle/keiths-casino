import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/empty_state_widget.dart';
import '../widgets/info_stat_tile.dart';
import '../widgets/section_card.dart';

class MatchesScreen extends StatelessWidget {
  MatchesScreen({super.key});

  String _fmtPlayedAt(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return ts.toDate().toLocal().toString().split('.').first;
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

  Color _coinDeltaColor(int value) {
    if (value > 0) return Colors.green.shade700;
    if (value < 0) return Colors.red.shade700;
    return Colors.black54;
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

  IconData _gameIcon(String gameType) {
    final lower = gameType.toLowerCase();
    if (lower.contains('poker')) return Icons.table_bar_rounded;
    return Icons.casino_rounded;
  }

  String _modeLabel(String mode) {
    if (mode.isEmpty) return 'Unknown';
    return mode[0].toUpperCase() + mode.substring(1);
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  int _safeInt(Map<String, dynamic> data, String key) {
    return ((data[key] ?? 0) as num).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
//Reads users/{uid}/matches/ Reads completed matches
    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('matches')
        .orderBy('playedAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Matches'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.history_toggle_off_rounded,
              title: 'No matches yet',
              subtitle: 'Your completed games will appear here.',
            );
          }

          int wins = 0;
          int losses = 0;
          int pushes = 0;
          int totalCoinDelta = 0;

          for (final doc in docs) {
            final data = doc.data();
            final result = (data['result'] ?? '').toString();
            final coinDelta = ((data['coinDelta'] ?? 0) as num).toInt();

            if (result == 'Win') wins++;
            if (result == 'Loss') losses++;
            if (result == 'Push') pushes++;

            totalCoinDelta += coinDelta;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                'Match History',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Review your latest completed games, outcomes, and coin movement.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),

              SectionCard(
                title: 'Overview',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InfoStatTile(
                            label: 'Matches',
                            value: docs.length.toString(),
                            icon: Icons.history_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InfoStatTile(
                            label: 'Wins',
                            value: wins.toString(),
                            icon: Icons.emoji_events_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
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
                    const SizedBox(height: 12),
                    InfoStatTile(
                      label: 'Net coin change',
                      value: totalCoinDelta > 0
                          ? '+$totalCoinDelta'
                          : totalCoinDelta.toString(),
                      icon: Icons.monetization_on_outlined,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              ...docs.map((doc) {
                final data = doc.data();

                final played = _fmtPlayedAt(data['playedAt']);
                final gameType = (data['gameType'] ?? 'Unknown').toString();
                final result = (data['result'] ?? '-').toString();
                final mode = (data['mode'] ?? '').toString();
                final coinDelta = ((data['coinDelta'] ?? 0) as num).toInt();
                final roomId = (data['roomId'] ?? '').toString();
                final opponentCount =
                ((data['opponentCount'] ?? 0) as num).toInt();

                final isPoker = gameType.toLowerCase().contains('poker');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SectionCard(
                    title: gameType,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _resultSoftBg(result),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        result,
                        style: TextStyle(
                          color: _resultColor(result),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.black.withOpacity(0.05),
                              child: Icon(_gameIcon(gameType), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    played,
                                    style:
                                    Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Mode: ${_modeLabel(mode)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              coinDelta > 0
                                  ? '+$coinDelta'
                                  : coinDelta.toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: _coinDeltaColor(coinDelta),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (mode == 'multiplayer')
                              _metaChip(
                                'Opponents: ${opponentCount < 1 ? 1 : opponentCount}',
                              ),
                            if (mode == 'multiplayer' && roomId.isNotEmpty)
                              _metaChip('Room: $roomId'),
                            if (!isPoker) ...[
                              _metaChip(
                                'Bet: ${_safeInt(data, 'bet')}',
                              ),
                              _metaChip(
                                'You: ${_safeInt(data, 'playerTotal')}',
                              ),
                              _metaChip(
                                'Dealer: ${_safeInt(data, 'dealerTotal')}',
                              ),
                            ] else ...[
                              _metaChip(
                                'Start: ${_safeInt(data, 'startingCoins')}',
                              ),
                              _metaChip(
                                'End: ${_safeInt(data, 'endingCoins')}',
                              ),
                              _metaChip(
                                'Pot: ${_safeInt(data, 'potAtEnd')}',
                              ),
                              if ((data['winningHandName'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _metaChip(
                                  'Hand: ${(data['winningHandName']).toString()}',
                                ),
                              if ((data['phaseEnded'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _metaChip(
                                  'Ended: ${(data['phaseEnded']).toString()}',
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}