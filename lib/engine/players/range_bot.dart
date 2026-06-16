import '../game/action.dart';
import '../game/game_view.dart';
import 'poker_player.dart';

/// The bot's possible moves, used both to act and to render its range.
enum BotMove { fold, check, call, pot }

/// A fully transparent, range-based bot for the heads-up trainer.
///
/// Its strategy is a simple set of rank thresholds, so it can be displayed to
/// the player as coloured ranges and explained in words. The bot plays the
/// button (small blind) and acts first.
class RangeBot implements PokerPlayer {
  RangeBot({this.id = 'range_bot', this.name = 'Dex'});

  @override
  final String id;
  @override
  final String name;

  /// First in (nothing to call): pot a [openPotFrom] or better, else check.
  static const int openPotFrom = 9; // a nine

  /// Facing a bet/raise: fold below [facingCallFrom], call up to (not incl.)
  /// [facingPotFrom], pot/shove at [facingPotFrom]+.
  static const int facingCallFrom = 10; // a ten
  static const int facingPotFrom = 14; // the ace

  /// What the bot intends to do with [rankValue] at the node implied by
  /// [facingBet]. Pure + static so the UI can render the exact same logic.
  static BotMove moveFor({required bool facingBet, required int rankValue}) {
    if (facingBet) {
      if (rankValue >= facingPotFrom) return BotMove.pot;
      if (rankValue >= facingCallFrom) return BotMove.call;
      return BotMove.fold;
    }
    if (rankValue >= openPotFrom) return BotMove.pot;
    return BotMove.check;
  }

  @override
  GameAction decide(GameView view) {
    final facing = view.toCall > 0;
    final move = moveFor(facingBet: facing, rankValue: view.myCard.rank.value);
    switch (move) {
      case BotMove.pot:
        if (view.canBet) return const GameAction.bet(0); // pot-sized
        // Can't raise (already all-in territory) — call if facing, else check.
        return facing ? GameAction.call(view.toCall) : const GameAction.check();
      case BotMove.call:
        return facing ? GameAction.call(view.toCall) : const GameAction.check();
      case BotMove.check:
        return const GameAction.check();
      case BotMove.fold:
        return facing ? const GameAction.fold() : const GameAction.check();
    }
  }
}
