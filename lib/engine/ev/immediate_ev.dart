import '../cards/card.dart';
import '../cards/rank.dart';
import '../cards/suit.dart';
import '../game/action.dart';
import '../game/hand_engine.dart';
import '../game/hand_state.dart';
import '../players/bot_profile.dart';
import '../players/range_bot.dart' show BotMove;

/// One villain card's immediate result for a hero action — **option A**: the
/// chips hero ends the hand with minus hero's stack at the start of the hand
/// (i.e. net profit), for every line that *resolves the moment the villain
/// answers*.
class ImmediateEv {
  const ImmediateEv(this.ev, this.label);

  /// Net chips, signed. Profit (+) or loss (−) from the start of the hand.
  final int ev;

  /// Short strategic label describing *this card's* result for hero's action —
  /// what kind of spot it is, not just the outcome. Depends on hero's action,
  /// the villain's transparent reply, and who's ahead:
  ///
  /// Hero bets/raises, villain **folds**:
  ///   worse card → `No Value` · same card → `Split Fold Eq` · better → `Fold Equity`
  /// Hero bets/raises, villain **calls** (showdown):
  ///   worse → `Value` · same → `Split` · better → `Called by Better`
  /// Hero **calls** (showdown):
  ///   ahead → `Showdown Value` · behind → `Paid Off` · tie → `Split`
  /// Hero **checks / folds**: no label (empty) — nothing to teach there.
  final String label;
}

/// Per-card *immediate* EV against a fully transparent [BotProfile].
///
/// For each card the villain might hold we play hero's action and the villain's
/// single transparent reply on a cloned [HandEngine] state, then read the
/// option-A result (end-of-hand chips minus start-of-hand stack). The catch the
/// trainer is built around: when hero's action **hands the decision back to
/// hero** — hero bets/raises and the villain *re-raises*, or hero checks and the
/// villain *bets* — the outcome depends on a move hero hasn't made yet, so we
/// deliberately return `null` ("?"). We never model the player's future for
/// them; that's the next decision to think through.
///
/// All chip arithmetic comes from committed amounts at the resolved node (the
/// same basis as [HandEngine] settlement), so the numbers can't drift from how a
/// hand actually plays.
class ImmediateEvCalculator {
  ImmediateEvCalculator(this.engine, this.profile,
      {required this.heroSeat, required this.botSeat});

  final HandEngine engine;
  final BotProfile profile;
  final int heroSeat;
  final int botSeat;

  /// Hero holds [heroCard]; returns the immediate result of [action] against
  /// each villain rank in [belief]. A `null` entry means the ball comes back to
  /// hero (shown as "?").
  Map<int, ImmediateEv?> evaluate(
    HandState state,
    int heroCard,
    List<int> belief,
    ActionType action,
  ) {
    return {
      for (final b in belief) b: _forCard(state, heroCard, b, action),
    };
  }

  ImmediateEv? _forCard(
      HandState state, int heroCard, int villainCard, ActionType action) {
    final s = state.clone();
    _setCards(s, heroCard, villainCard);
    engine.applyAction(s, GameAction(action));

    // The villain answers once, if it's its turn.
    if (s.phase == HandPhase.betting && s.toAct == botSeat) {
      final move = profile.moveAt(_nodeFor(s, botSeat), villainCard);
      engine.applyAction(s, _villainAction(s, botSeat, move));
    }

    // Ball back in hero's court → unknown; we don't model hero's next move.
    if (s.phase == HandPhase.betting && s.toAct == heroSeat) return null;

    return _terminal(s, heroCard, villainCard, action);
  }

  /// Hero's net profit from the start of the hand at a resolved node, plus a
  /// strategic label for the spot (see [ImmediateEv.label]). A fold returns the
  /// folder's own chips, so the winner's profit is exactly the loser's committed
  /// chips (an uncalled bet comes straight back).
  ImmediateEv _terminal(
      HandState s, int heroCard, int villainCard, ActionType action) {
    final hero = s.seats[heroSeat];
    final villain = s.seats[botSeat];

    // bet == bet-or-raise (a pot is a bet here); call is a showdown call.
    // Check/fold are passive — no teaching label.
    final aggressed = action == ActionType.bet;
    final called = action == ActionType.call;

    // We folded — we lose what we put in. No comment.
    if (hero.folded) return ImmediateEv(-hero.committed, '');

    // We bet/raised and the villain folded — fold-equity spot, graded by the
    // card he gave up.
    if (villain.folded) {
      final label = !aggressed
          ? ''
          : heroCard > villainCard
              ? 'No Value' // he folded a worse hand — we won nothing extra
              : heroCard == villainCard
                  ? 'Split Fold Eq' // he folded the chop
                  : 'Fold Equity'; // we made a better hand fold
      return ImmediateEv(villain.committed, label);
    }

    // Showdown.
    if (heroCard == villainCard) {
      return ImmediateEv(0, (aggressed || called) ? 'Split' : '');
    }
    final matched =
        hero.committed < villain.committed ? hero.committed : villain.committed;
    final ahead = heroCard > villainCard;
    final label = aggressed
        ? (ahead ? 'Value' : 'Called by Better')
        : called
            ? (ahead ? 'Showdown Value' : 'Paid Off')
            : ''; // checked to showdown — no comment
    return ImmediateEv(ahead ? matched : -matched, label);
  }

  // ---- Helpers (shared shape with EvCalculator) ---------------------------

  void _setCards(HandState s, int heroCard, int villainCard) {
    s.seats[heroSeat].card = PlayingCard(_rankOf(heroCard), Suit.spades);
    s.seats[botSeat].card = PlayingCard(_rankOf(villainCard), Suit.hearts);
  }

  Rank _rankOf(int value) => Rank.values.firstWhere((r) => r.value == value);

  BetNode _nodeFor(HandState s, int seatIndex) {
    final seat = s.seats[seatIndex];
    final toCall = s.currentBet - seat.committed;
    if (toCall > 0) {
      if (s.raiseCount <= 1) return BetNode.facingBet;
      if (s.raiseCount == 2) return BetNode.facingRaise;
      return BetNode.facingReraise;
    }
    final other = s.seats[seatIndex == botSeat ? heroSeat : botSeat];
    return other.lastAction?.type == ActionType.check
        ? BetNode.checkedTo
        : BetNode.open;
  }

  /// Turns an intended [BotMove] into a legal [GameAction], degrading gracefully
  /// when a raise isn't possible (already all-in for less).
  GameAction _villainAction(HandState s, int seatIndex, BotMove move) {
    final seat = s.seats[seatIndex];
    final toCall = s.currentBet - seat.committed;
    final canBet = seat.stack > toCall;
    switch (move) {
      case BotMove.pot:
        if (canBet) return const GameAction.bet(0);
        return toCall > 0 ? const GameAction.call(0) : const GameAction.check();
      case BotMove.call:
        return toCall > 0 ? const GameAction.call(0) : const GameAction.check();
      case BotMove.check:
        return const GameAction.check();
      case BotMove.fold:
        return toCall > 0 ? const GameAction.fold() : const GameAction.check();
    }
  }
}
