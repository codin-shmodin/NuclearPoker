/// The kinds of moves a player can make in simple one-card poker.
enum ActionType { fold, check, call, bet }

/// A single decision by a player. [amount] is the chips committed for `bet`/`call`
/// (0 for `fold`/`check`).
class GameAction {
  const GameAction(this.type, [this.amount = 0]);

  const GameAction.fold() : this(ActionType.fold);
  const GameAction.check() : this(ActionType.check);
  const GameAction.call(int amount) : this(ActionType.call, amount);
  const GameAction.bet(int amount) : this(ActionType.bet, amount);

  final ActionType type;
  final int amount;

  @override
  String toString() {
    switch (type) {
      case ActionType.bet:
        return 'Bet $amount';
      case ActionType.call:
        return 'Call $amount';
      case ActionType.check:
        return 'Check';
      case ActionType.fold:
        return 'Fold';
    }
  }
}
