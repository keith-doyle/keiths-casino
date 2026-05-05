class GameAdCounterService {
  static int _completedGames = 0;
//Used to avoid showing an interstitial after every single game.
  static bool shouldShowAdAfterCompletedGame() {
    _completedGames += 1;
    return _completedGames % 2 == 0;
  }
//Sets completed games counter back to 0
  static void reset() {
    _completedGames = 0;
  }
}