import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  static const String _baseUrl = 'http://16.170.162.140:8000';

  bool _busy = false;
  String? _error;

  Future<void> _startCheckout(String plan) async {
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
        Uri.parse('$_baseUrl/billing/create-checkout-session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': user.uid,
          'email': user.email ?? '',
          'plan': plan,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? response.body);
      }

      final checkoutUrl = data['checkoutUrl']?.toString();

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('Checkout URL missing');
      }

      final uri = Uri.parse(checkoutUrl);

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Could not open checkout page');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start checkout. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _benefit(IconData icon, String title, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF6D28D9)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(text),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planCard({
    required String title,
    required String price,
    required String subtitle,
    required String plan,
    required bool highlighted,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted ? const Color(0xFF7C3AED) : Colors.transparent,
          width: 2,
        ),
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
          if (highlighted)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Best value',
                style: TextStyle(
                  color: Color(0xFF7C3AED),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            price,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
          ),
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : () => _startCheckout(plan),
              child: Text(_busy ? 'Opening...' : 'Choose $title'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF4F46E5),
                  Color(0xFF7C3AED),
                ],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 42),
                SizedBox(height: 14),
                Text(
                  'Upgrade to Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Remove ads, unlock boosted daily rewards, and support the platform.',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _benefit(
            Icons.block_rounded,
            'Ad-free experience',
            'Premium users do not see banner ads or video ads.',
          ),
          const SizedBox(height: 16),
          _benefit(
            Icons.card_giftcard_rounded,
            'Boosted daily rewards',
            'Premium users receive higher streak-based coin rewards.',
          ),
          const SizedBox(height: 16),
          _benefit(
            Icons.verified_rounded,
            'Premium status',
            'Your account is upgraded through Stripe and stored securely in Firestore.',
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
          const SizedBox(height: 24),
          _planCard(
            title: 'Monthly',
            price: '€4.99',
            subtitle: 'Flexible monthly premium membership.',
            plan: 'monthly',
            highlighted: false,
          ),
          const SizedBox(height: 16),
          _planCard(
            title: 'Yearly',
            price: '€39.99',
            subtitle: 'Best value for long-term players.',
            plan: 'yearly',
            highlighted: true,
          ),
        ],
      ),
    );
  }
}