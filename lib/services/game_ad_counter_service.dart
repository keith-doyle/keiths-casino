class GameAdCounterService {
  static int _completedGames = 0;

  static bool shouldShowAdAfterCompletedGame() {
    _completedGames += 1;
    return _completedGames % 2 == 0;
  }

  static void reset() {
    _completedGames = 0;
  }
}