/// Tunable rules for a one-card-poker hand. Designed to be driven by Firebase
/// Remote Config later so difficulty/economy can change without an app update.
class RuleConfig {
  const RuleConfig({
    this.ante = 0,
    this.smallBlind = 0,
    this.bigBlind = 0,
    this.startingStack = 100,
    this.maxPlayers = 6,
  });

  /// Chips every player posts before cards are dealt. 0 when using blinds.
  final int ante;

  /// Forced bet posted by the seat left of the button (0 if unused).
  final int smallBlind;

  /// Forced bet posted by the next seat; sets the opening bet (0 if unused).
  final int bigBlind;

  /// Note: bets/raises are **pot-sized** (the raise adds one current pot), so
  /// there is no fixed bet size. Raising is uncapped — it only stops when stacks
  /// run out (you shove all-in for whatever you have left).

  /// Chips each player starts a session with.
  final int startingStack;

  /// Hard cap on seats at the table.
  final int maxPlayers;
}
