import '../../engine/players/bot_profile.dart' show BetNode;
import '../../engine/players/range_bot.dart' show BotMove;

/// Which seat the decision was made from. Heads-up has exactly two: the button
/// (you act first) and the big blind (you act after the opponent). The *same*
/// [BetNode] means different things in each seat — "facing a bet" as the BTN is
/// the opponent 3-betting your open, but as the BB it's the opponent's first
/// bet — so a saved line must be keyed by position or the two ranges bleed into
/// each other. See docs/heads-up-trainer.md.
enum LinePosition { btn, bb }

/// The player's own saved strategy for a level — the mirror of a [BotProfile],
/// but holding the *concrete* action chosen for each (position, spot, card)
/// instead of rank thresholds. Built by "capturing" the player's decisions hand
/// by hand (see docs/expansion-plans.md §1), then handed back to the controller
/// so the player's own bot can "auto-play" the line.
///
/// Keyed by [LinePosition] (which seat you were in) then [BetNode] (the decision
/// spot — open / facing a bet / …) then the card's [Rank.value] (2..14). The
/// stored action reuses [BotMove] (fold / check / call / pot) so the controller
/// can apply it through the same path it uses for the transparent bots.
class HumanLine {
  HumanLine([Map<LinePosition, Map<BetNode, Map<int, BotMove>>>? moves])
      : _moves = moves ?? <LinePosition, Map<BetNode, Map<int, BotMove>>>{};

  final Map<LinePosition, Map<BetNode, Map<int, BotMove>>> _moves;

  /// The saved action for [rankValue] at [node] in [pos], or null if this spot
  /// has never been captured.
  BotMove? moveAt(LinePosition pos, BetNode node, int rankValue) =>
      _moves[pos]?[node]?[rankValue];

  /// Bind [move] to ([pos], [node], [rankValue]), overwriting any previous one.
  void record(LinePosition pos, BetNode node, int rankValue, BotMove move) {
    ((_moves[pos] ??= <BetNode, Map<int, BotMove>>{})[node] ??=
        <int, BotMove>{})[rankValue] = move;
  }

  /// Forget the action saved at ([pos], [node], [rankValue]), if any — used by
  /// the editor when a cell cycles back to its blank state.
  void clear(LinePosition pos, BetNode node, int rankValue) {
    _moves[pos]?[node]?.remove(rankValue);
  }

  /// Fold every entry of [other] into this line (other wins on conflict).
  void merge(HumanLine other) {
    other._moves.forEach((pos, byNode) {
      byNode.forEach((node, byRank) {
        byRank.forEach((rank, move) => record(pos, node, rank, move));
      });
    });
  }

  bool get isEmpty =>
      _moves.values.every((byNode) => byNode.values.every((m) => m.isEmpty));

  /// Total number of captured (position, spot, card) decisions.
  int get count => _moves.values.fold(
        0,
        (sum, byNode) =>
            sum + byNode.values.fold(0, (s, m) => s + m.length),
      );

  Map<String, dynamic> toJson() => {
        for (final pos in _moves.entries)
          if (pos.value.values.any((m) => m.isNotEmpty))
            pos.key.name: {
              for (final e in pos.value.entries)
                if (e.value.isNotEmpty)
                  e.key.name: {
                    for (final m in e.value.entries) '${m.key}': m.value.name,
                  },
            },
      };

  factory HumanLine.fromJson(Map<String, dynamic> json) {
    final moves = <LinePosition, Map<BetNode, Map<int, BotMove>>>{};
    json.forEach((posName, nodeMap) {
      final pos = _byName(LinePosition.values, posName);
      if (pos == null || nodeMap is! Map) return;
      final byNode = <BetNode, Map<int, BotMove>>{};
      nodeMap.forEach((nodeName, rankMap) {
        final node = _byName(BetNode.values, '$nodeName');
        if (node == null || rankMap is! Map) return;
        final inner = <int, BotMove>{};
        rankMap.forEach((rank, moveName) {
          final r = int.tryParse('$rank');
          final move = _byName(BotMove.values, '$moveName');
          if (r != null && move != null) inner[r] = move;
        });
        if (inner.isNotEmpty) byNode[node] = inner;
      });
      if (byNode.isNotEmpty) moves[pos] = byNode;
    });
    return HumanLine(moves);
  }
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
