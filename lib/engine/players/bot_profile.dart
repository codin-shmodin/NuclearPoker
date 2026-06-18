import 'range_bot.dart' show BotMove;

/// A decision node in the single-round heads-up betting tree, identified by what
/// the acting player faces. This is the key into a bot's strategy table — and
/// it's exactly the set of spots you asked for:
///
/// - [open]          — first to act, nothing to call (you "act first").
/// - [checkedTo]     — the opponent checked to you (you "act after a check").
/// - [facingBet]     — facing the opponent's bet/open (you "act after a bet").
/// - [facingRaise]   — you bet, the opponent raised: a 3-bet at you.
/// - [facingReraise] — a 4-bet+ (you raised, got re-raised).
enum BetNode { open, checkedTo, facingBet, facingRaise, facingReraise }

bool _isFacing(BetNode node) =>
    node == BetNode.facingBet ||
    node == BetNode.facingRaise ||
    node == BetNode.facingReraise;

/// The bot's plan at one node, as plain rank thresholds plus an optional set of
/// low-card "bluffs" promoted to the aggressive action. Ranks use [Rank.value]
/// (2..14, ace high).
///
/// - Passive node (open / checkedTo): bet (pot) at/above [betFrom], else check.
/// - Facing node: raise (pot) at/above [raiseFrom], call at/above [callFrom],
///   else fold.
/// - [bluffs] are extra ranks (typically the bottom) promoted to the aggressive
///   action — this is what makes a range *polarised* (value + bluffs) rather
///   than a single linear threshold, and it's how the personalities differ.
class NodeStrategy {
  const NodeStrategy({
    this.betFrom = 99,
    this.callFrom = 99,
    this.raiseFrom = 99,
    this.bluffs = const {},
  });

  final int betFrom;
  final int callFrom;
  final int raiseFrom;
  final Set<int> bluffs;

  BotMove moveFor(int rankValue, {required bool facing}) {
    final aggressive =
        rankValue >= (facing ? raiseFrom : betFrom) || bluffs.contains(rankValue);
    if (facing) {
      if (aggressive) return BotMove.pot;
      if (rankValue >= callFrom) return BotMove.call;
      return BotMove.fold;
    }
    return aggressive ? BotMove.pot : BotMove.check;
  }
}

/// A complete, transparent bot personality: one [NodeStrategy] per [BetNode],
/// stored as a table so the UI can render it, the engine can play it, and the
/// EV evaluator can read it — all from the same source.
class BotProfile {
  const BotProfile({
    required this.id,
    required this.name,
    required this.blurb,
    required this.nodes,
  });

  final String id;
  final String name;
  final String blurb;
  final Map<BetNode, NodeStrategy> nodes;

  /// What this bot does with [rankValue] at [node].
  BotMove moveAt(BetNode node, int rankValue) =>
      (nodes[node] ?? const NodeStrategy())
          .moveFor(rankValue, facing: _isFacing(node));

  // ---- The three personalities -------------------------------------------

  /// Tight-passive: only plays premiums, never bluffs, folds to any pressure.
  /// Easy to beat by betting wide — folds far too much.
  static const BotProfile rock = BotProfile(
    id: 'rock',
    name: 'Rocky',
    blurb: 'Tight & passive — only premiums, never bluffs, folds to pressure.',
    nodes: {
      BetNode.open: NodeStrategy(betFrom: 12), // bets Q+ only
      BetNode.checkedTo: NodeStrategy(betFrom: 12),
      BetNode.facingBet: NodeStrategy(callFrom: 13, raiseFrom: 14), // call K, shove A
      BetNode.facingRaise: NodeStrategy(callFrom: 14, raiseFrom: 99), // only A continues
      BetNode.facingReraise: NodeStrategy(callFrom: 14, raiseFrom: 99),
    },
  );

  /// Loose-aggressive maniac: bets/raises a huge range, bluffs the bottom,
  /// defends far too wide. Punishes you for folding; bluffs back at you.
  static const BotProfile maniac = BotProfile(
    id: 'maniac',
    name: 'Vex',
    blurb: 'Loose & aggressive — bets wide, bluffs the bottom, defends too much.',
    nodes: {
      BetNode.open: NodeStrategy(betFrom: 7, bluffs: {2, 3}),
      BetNode.checkedTo: NodeStrategy(betFrom: 6, bluffs: {2, 3, 4}),
      BetNode.facingBet: NodeStrategy(callFrom: 6, raiseFrom: 11, bluffs: {2, 3}),
      BetNode.facingRaise: NodeStrategy(callFrom: 9, raiseFrom: 13, bluffs: {2}),
      BetNode.facingReraise: NodeStrategy(callFrom: 11, raiseFrom: 14),
    },
  );

  /// Balanced / polarised: value top + a few bottom bluffs, calls a sensible
  /// middle, defends roughly enough that you can't print by betting any two.
  static const BotProfile pro = BotProfile(
    id: 'pro',
    name: 'Sage',
    blurb: 'Balanced — polarised value & bluffs, defends about the right amount.',
    nodes: {
      BetNode.open: NodeStrategy(betFrom: 10, bluffs: {2, 3}),
      BetNode.checkedTo: NodeStrategy(betFrom: 9, bluffs: {2}),
      BetNode.facingBet: NodeStrategy(callFrom: 9, raiseFrom: 13, bluffs: {2}),
      BetNode.facingRaise: NodeStrategy(callFrom: 11, raiseFrom: 14),
      BetNode.facingReraise: NodeStrategy(callFrom: 13, raiseFrom: 14),
    },
  );

  static const List<BotProfile> all = [rock, maniac, pro];
}
