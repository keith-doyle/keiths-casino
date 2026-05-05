import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/interstitial_ad_service.dart';
import 'theme/app_theme.dart';
//initializes flutter binding firebase + mobile ads and interstitial ads
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await MobileAds.instance.initialize();
  await InterstitialAdService.load();
  runApp(const MyApp());
}
//Uses materialapp to set home to authgate
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    //Material app wraps in flutter material design, applies theme, title and sets auth gate
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Keith's Casino",
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}
//Authgate listens to firebaseAuth + authStateChanges
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
//no user means authScreen, signed in users are brought to homescreen
        final user = snap.data;
        if (user == null) {
          return AuthScreen();
        }

        return HomeScreen();
      },
    );
  }
}