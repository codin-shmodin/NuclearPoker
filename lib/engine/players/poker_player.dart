import '../game/action.dart';
import '../game/game_view.dart';

/// The single seam every AI personality (and, conceptually, the human) sits
/// behind. Adding a new opponent — or swapping the simple AI for a GTO bot
/// later — means writing one class, nothing else changes.
abstract class PokerPlayer {
  String get id;
  String get name;

  /// Given only what this player is allowed to see, return a legal action.
  GameAction decide(GameView view);
}
