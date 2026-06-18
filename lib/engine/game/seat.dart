import '../cards/card.dart';
import 'action.dart';

/// A seat at the table and its mutable per-hand state. One seat per participant
/// (human or AI). Stack persists across hands; the rest is reset each hand.
class Seat {
  Seat({
    required this.index,
    required this.playerId,
    required this.name,
    required this.isHuman,
    required this.stack,
  });

  final int index;
  final String playerId;
  final String name;
  final bool isHuman;

  int stack;

  // Reset every hand:
  PlayingCard? card;
  bool folded = false;
  bool hasActed = false;
  int committed = 0; // chips put into the current betting round
  int lastWin = 0; // chips won in the most recent settled hand (for UI)
  GameAction? lastAction; // most recent action this hand (for UI)

  void resetForHand() {
    card = null;
    folded = false;
    hasActed = false;
    committed = 0;
    lastWin = 0;
    lastAction = null;
  }

  /// A deep copy of this seat's full state. Used by the EV evaluator to explore
  /// hypothetical lines without disturbing the live hand.
  Seat clone() => Seat(
        index: index,
        playerId: playerId,
        name: name,
        isHuman: isHuman,
        stack: stack,
      )
        ..card = card
        ..folded = folded
        ..hasActed = hasActed
        ..committed = committed
        ..lastWin = lastWin
        ..lastAction = lastAction;
}
