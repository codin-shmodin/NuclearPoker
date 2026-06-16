import '../cards/card.dart';
import 'action.dart';

/// A redacted snapshot of another seat — only public information.
class OpponentView {
  const OpponentView({
    required this.seatIndex,
    required this.name,
    required this.stack,
    required this.folded,
    required this.committed,
    required this.lastAction,
  });

  final int seatIndex;
  final String name;
  final int stack;
  final bool folded;
  final int committed;
  final GameAction? lastAction;
}

/// Exactly what one player (human or AI) is allowed to see when it's their turn
/// to act. Bots receive this and nothing else — they cannot peek at hole cards.
class GameView {
  const GameView({
    required this.myCard,
    required this.mySeatIndex,
    required this.myStack,
    required this.pot,
    required this.toCall,
    required this.currentBet,
    required this.canCheck,
    required this.canCall,
    required this.canBet,
    required this.raiseTarget,
    required this.isOpen,
    required this.raiseCount,
    required this.activePlayers,
    required this.opponents,
  });

  final PlayingCard myCard;
  final int mySeatIndex;
  final int myStack;
  final int pot;
  final int toCall;
  final int currentBet;
  final bool canCheck;
  final bool canCall;

  /// Whether the player may be aggressive (open a bet or raise).
  final bool canBet;

  /// The total commitment if the player bets/raises (capped by all-in).
  final int raiseTarget;

  /// True if no one has bet/raised yet this round (label "Bet" vs "Raise").
  final bool isOpen;

  /// Aggressive actions so far this round.
  final int raiseCount;

  final int activePlayers;
  final List<OpponentView> opponents;
}
