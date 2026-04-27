import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailC = TextEditingController();
  final _passwordC = TextEditingController();
  final _usernameC = TextEditingController();

  bool _isLogin = true;
  bool _busy = false;
  String? _error;

  Future<bool> _usernameAvailable(String username) async {
    final unameLower = username.trim().toLowerCase();
    if (unameLower.length < 3) return false;

    final doc = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(unameLower)
        .get();

    return !doc.exists;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailC.text.trim(),
          password: _passwordC.text.trim(),
        );
        return;
      }

      final username = _usernameC.text.trim();
      final unameLower = username.toLowerCase();

      final ok = await _usernameAvailable(username);
      if (!ok) {
        setState(() => _error = 'That username is already taken.');
        return;
      }

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailC.text.trim(),
        password: _passwordC.text.trim(),
      );
      final uid = cred.user!.uid;

      final users = FirebaseFirestore.instance.collection('users');
      final usernames = FirebaseFirestore.instance.collection('usernames');

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final unameRef = usernames.doc(unameLower);
        final unameSnap = await tx.get(unameRef);

        if (unameSnap.exists) throw StateError('USERNAME_TAKEN_RACE');

        tx.set(unameRef, {
          'uid': uid,
          'username': username,
          'createdAt': FieldValue.serverTimestamp(),
        });

        tx.set(users.doc(uid), {
          'username': username,
          'usernameLower': unameLower,
          'email': _emailC.text.trim(),
          'photoUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
          'friends': [],
          'coins': 1000,

          'isPremium': false,
          'premiumTier': 'free',
          'premiumStatus': 'free',
          'premiumSource': 'none',
          'stripeCustomerId': null,
          'stripeSubscriptionId': null,
          'stripePriceId': null,
          'premiumUpdatedAt': null,
          'premiumExpiresAt': null,

          'loginStreak': 0,
          'lastLoginReward': null,
          'lastLoginRewardAmount': 0,
          'lastLoginRewardWasPremium': false,
        });
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } on StateError catch (e) {
      if (e.message == 'USERNAME_TAKEN_RACE') {
        await FirebaseAuth.instance.currentUser?.delete();
        setState(() {
          _error = 'That username was just taken. Please choose another.';
        });
      } else {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passwordC.dispose();
    _usernameC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isLogin ? 'Welcome back' : 'Create account';
    final subtitle = _isLogin
        ? 'Sign in to continue to your card platform.'
        : 'Create your account and start building your match history.';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF6F7FB),
              Color(0xFFEFF1FA),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      height: 66,
                      width: 66,
                      decoration: AppTheme.gradientHeroDecoration,
                      child: const Icon(
                        Icons.style_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Card Games Compendium',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: AppTheme.softCardDecoration,
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 18),
                            if (!_isLogin) ...[
                              TextFormField(
                                controller: _usernameC,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.alternate_email),
                                ),
                                validator: (v) =>
                                (v == null || v.trim().length < 3)
                                    ? 'Min 3 chars'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailC,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                              ),
                              validator: (v) => (v == null || !v.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordC,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Min 6 chars'
                                  : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.18),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy
                                    ? 'Please wait...'
                                    : (_isLogin ? 'Login' : 'Register'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _isLogin = !_isLogin),
                                child: Text(
                                  _isLogin
                                      ? 'Need an account? Register'
                                      : 'Have an account? Login',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}