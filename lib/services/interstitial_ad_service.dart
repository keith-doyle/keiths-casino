import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'game_ad_counter_service.dart';

class InterstitialAdService {
  static InterstitialAd? _interstitialAd;
  static bool _isLoading = false;

  static const String _testInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
//Loads google test interstitial ad
  static Future<void> load() async {
    if (_isLoading || _interstitialAd != null) return;

    _isLoading = true;

    await InterstitialAd.load(
      adUnitId: _testInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }
//reads if isPremium is true or false before deciding to show the ad
  static Future<bool> _currentUserIsPremium() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return false;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();

    return data?['isPremium'] == true;
  }
//Checks premium status, checks ad counter loads if needed
  static Future<void> handleCompletedGame() async {
    final isPremium = await _currentUserIsPremium();

    if (isPremium) {
      return;
    }

    final shouldShowAd = GameAdCounterService.shouldShowAdAfterCompletedGame();

    if (!shouldShowAd) {
      return;
    }

    if (_interstitialAd == null) {
      await load();
      return;
    }

    final ad = _interstitialAd;
    _interstitialAd = null;

    ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        load();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        load();
      },
    );

    await ad.show();
  }
//Disposes loaded interstitial ad and clears reference
  static void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}