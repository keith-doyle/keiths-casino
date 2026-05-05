import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class ManagePremiumScreen extends StatefulWidget {
  const ManagePremiumScreen({super.key});

  @override
  State<ManagePremiumScreen> createState() => _ManagePremiumScreenState();
}

class _ManagePremiumScreenState extends State<ManagePremiumScreen> {
  static const String _baseUrl = 'http://16.170.162.140:8000';

  bool _busy = false;
  String? _error;
//posts uid to /billing/create-portal/session opens stripe billing portal
  Future<void> _openBillingPortal() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _error = 'You must be signed in.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/billing/create-portal-session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': user.uid,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? response.body);
      }

      final portalUrl = data['portalUrl']?.toString();

      if (portalUrl == null || portalUrl.isEmpty) {
        throw Exception('Billing portal URL missing');
      }

      final opened = await launchUrl(
        Uri.parse(portalUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Could not open billing portal');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open subscription management. Please try again.';
      });
    }
    finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
  //Stream current user's premium fields and display tier/status and manage subscription
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Premium'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDoc.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();

          final tier = (data?['premiumTier'] ?? 'premium').toString();
          final status = (data?['premiumStatus'] ?? 'active').toString();
          final source = (data?['premiumSource'] ?? 'stripe').toString();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFF59E0B),
                      Color(0xFF7C3AED),
                    ],
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Premium Active',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your account is currently upgraded. Ads are removed while your subscription is active.',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              _infoTile(
                icon: Icons.verified_rounded,
                title: 'Subscription status',
                value: status,
              ),
              const SizedBox(height: 12),
              _infoTile(
                icon: Icons.star_rounded,
                title: 'Plan',
                value: tier,
              ),
              const SizedBox(height: 12),
              _infoTile(
                icon: Icons.payment_rounded,
                title: 'Billing provider',
                value: source,
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manage subscription',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Open the secure Stripe billing portal to cancel or manage your premium subscription.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _openBillingPortal,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: Text(
                          _busy ? 'Opening...' : 'Open Billing Portal',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 18),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],

              const SizedBox(height: 18),

              const Text(
                'Cancellation is handled securely through Stripe. Your premium access should remain active until Stripe confirms the subscription has ended.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          );
        },
      ),
    );
  }
//Reusable row for subscription status
  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7C3AED)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}