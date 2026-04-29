import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DailyRewardCard extends StatefulWidget {
  const DailyRewardCard({super.key});

  @override
  State<DailyRewardCard> createState() => _DailyRewardCardState();
}

class _DailyRewardCardState extends State<DailyRewardCard> {
  static const String _baseUrl = 'http://16.170.162.140:8000';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  bool _loading = true;
  bool _claiming = false;
  bool _refreshing = false;
  String? _error;

  bool _canClaim = false;
  bool _isPremium = false;
  int _secondsUntilNextClaim = 0;
  int _loginStreak = 0;
  int _nextReward = 10;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();

    final uid = _uid;

    if (uid == null) {
      _loadRewardStatus();
      return;
    }

    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((_) {
      _loadRewardStatus();
    });
  }

  Future<void> _loadRewardStatus() async {
    final uid = _uid;

    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }

    if (_refreshing) return;
    _refreshing = true;

    if (mounted && _loading == false) {
      setState(() => _error = null);
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/rewards/status/$uid'),
      );

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        _canClaim = data['canClaim'] == true;
        _secondsUntilNextClaim =
            ((data['secondsUntilNextClaim'] ?? 0) as num).toInt();
        _loginStreak = ((data['loginStreak'] ?? 0) as num).toInt();
        _nextReward = ((data['nextReward'] ?? 10) as num).toInt();
        _isPremium = data['isPremium'] == true;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Reward unavailable';
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _claimReward() async {
    final uid = _uid;

    if (uid == null || !_canClaim || _claiming) return;

    setState(() {
      _claiming = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/rewards/claim-daily'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? response.body);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Claimed ${data['reward']} coins.'),
        ),
      );

      await _loadRewardStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not claim';
      });
    } finally {
      if (mounted) {
        setState(() {
          _claiming = false;
        });
      }
    }
  }

  String _timeRemainingLabel() {
    if (_secondsUntilNextClaim <= 0) return 'Available';

    final hours = _secondsUntilNextClaim ~/ 3600;
    final minutes = (_secondsUntilNextClaim % 3600) ~/ 60;

    if (hours <= 0) return '${minutes}m left';

    return '${hours}h ${minutes}m left';
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _pillShell(
        child: const SizedBox(
          height: 54,
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final title = _isPremium ? 'Premium Reward' : 'Daily Reward';
    final status = _error ??
        (_canClaim
            ? 'Claim $_nextReward coins'
            : '${_timeRemainingLabel()} • Streak $_loginStreak');

    return _pillShell(
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isPremium
                  ? Icons.workspace_premium_rounded
                  : Icons.card_giftcard_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _canClaim && !_claiming ? _claimReward : null,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _isPremium
                  ? const Color(0xFFB45309)
                  : const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              minimumSize: const Size(0, 38),
            ),
            child: Text(
              _claiming ? 'Claiming' : (_canClaim ? 'Claim' : 'Done'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: _isPremium
              ? [
            const Color(0xFFF59E0B),
            const Color(0xFFEA580C),
          ]
              : [
            const Color(0xFF42A5F5),
            const Color(0xFF2563EB),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}