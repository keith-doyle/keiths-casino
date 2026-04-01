import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            return const Center(child: Text("No matches yet."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data();

              final played = _fmtPlayedAt(data['playedAt']);
              final gameType = (data['gameType'] ?? 'Unknown').toString();
              final result = (data['result'] ?? '-').toString();
              final mode = (data['mode'] ?? '').toString();

              final bet = ((data['bet'] ?? 0) as num).toInt();
              final coinDelta = ((data['coinDelta'] ?? 0) as num).toInt();
              final playerTotal = ((data['playerTotal'] ?? 0) as num).toInt();
              final dealerTotal = ((data['dealerTotal'] ?? 0) as num).toInt();
              final roomId = (data['roomId'] ?? '').toString();
              final opponentCount =
              ((data['opponentCount'] ?? 0) as num).toInt();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.sports_esports),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gameType,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  played,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                result,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _resultColor(result),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                coinDelta > 0
                                    ? '+$coinDelta'
                                    : coinDelta.toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _coinDeltaColor(coinDelta),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _metaChip('Mode: ${_modeLabel(mode)}'),
                          _metaChip('Bet: $bet'),
                          _metaChip('You: $playerTotal'),
                          _metaChip('Dealer: $dealerTotal'),
                          if (mode == 'multiplayer')
                            _metaChip('Opponents: $opponentCount'),
                          if (mode == 'multiplayer' && roomId.isNotEmpty)
                            _metaChip('Room: $roomId'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}