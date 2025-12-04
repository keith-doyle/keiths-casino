import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
        });
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } on StateError catch (e) {
      if (e.message == 'USERNAME_TAKEN_RACE') {
        await FirebaseAuth.instance.currentUser?.delete();
        setState(() =>
        _error = 'That username was just taken. Please choose another.');
      } else {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login' : 'Create account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!_isLogin)
                TextFormField(
                  controller: _usernameC,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Min 3 chars' : null,
                ),
              TextFormField(
                controller: _emailC,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              TextFormField(
                controller: _passwordC,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) =>
                (v == null || v.length < 6) ? 'Min 6 chars' : null,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_isLogin ? 'Login' : 'Register'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin
                    ? 'Need an account? Register'
                    : 'Have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
