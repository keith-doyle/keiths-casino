import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/empty_state_widget.dart';
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('matches')
        .orderBy('playedAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('My Matches')),
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

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final data = docs[i].data();

              final played = _fmtPlayedAt(data['playedAt']);
              final gameType = (data['gameType'] ?? 'Unknown').toString();
              final result = (data['result'] ?? '-').toString();
              final mode = (data['mode'] ?? '').toString();
              final coinDelta = ((data['coinDelta'] ?? 0) as num).toInt();
              final roomId = (data['roomId'] ?? '').toString();
              final opponentCount = ((data['opponentCount'] ?? 0) as num).toInt();

              final isPoker = gameType.toLowerCase().contains('poker');

              return SectionCard(
                title: gameType,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            played,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          result,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _resultColor(result),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          coinDelta > 0 ? '+$coinDelta' : coinDelta.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
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
                        _metaChip('Mode: ${_modeLabel(mode)}'),
                        if (mode == 'multiplayer')
                          _metaChip('Opponents: ${opponentCount < 1 ? 1 : opponentCount}'),
                        if (mode == 'multiplayer' && roomId.isNotEmpty)
                          _metaChip('Room: $roomId'),

                        if (!isPoker) ...[
                          _metaChip('Bet: ${((data['bet'] ?? 0) as num).toInt()}'),
                          _metaChip('You: ${((data['playerTotal'] ?? 0) as num).toInt()}'),
                          _metaChip('Dealer: ${((data['dealerTotal'] ?? 0) as num).toInt()}'),
                        ] else ...[
                          _metaChip('Start: ${((data['startingCoins'] ?? 0) as num).toInt()}'),
                          _metaChip('End: ${((data['endingCoins'] ?? 0) as num).toInt()}'),
                          _metaChip('Pot: ${((data['potAtEnd'] ?? 0) as num).toInt()}'),
                          if ((data['winningHandName'] ?? '').toString().isNotEmpty)
                            _metaChip('Hand: ${(data['winningHandName']).toString()}'),
                          if ((data['phaseEnded'] ?? '').toString().isNotEmpty)
                            _metaChip('Ended: ${(data['phaseEnded']).toString()}'),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}