import '../../engine/players/bot_profile.dart' show BetNode;
import '../../engine/players/range_bot.dart' show BotMove;

/// The player's own saved strategy for a level — the mirror of a [BotProfile],
/// but holding the *concrete* action chosen for each (spot, card) instead of
/// rank thresholds. Built by "capturing" the player's decisions hand by hand
/// (see docs/expansion-plans.md §1), then handed back to the controller so the
/// player's own bot can "auto-play" the line.
///
/// Keyed by [BetNode] (the decision spot — open / facing a bet / …) then by the
/// card's [Rank.value] (2..14). The stored action reuses [BotMove] (fold / check
/// / call / pot) so the controller can apply it through the same path it uses
/// for the transparent bots.
class HumanLine {
  HumanLine([Map<BetNode, Map<int, BotMove>>? moves])
      : _moves = moves ?? <BetNode, Map<int, BotMove>>{};

  final Map<BetNode, Map<int, BotMove>> _moves;

  /// The saved action for [rankValue] at [node], or null if this spot has never
  /// been captured.
  BotMove? moveAt(BetNode node, int rankValue) => _moves[node]?[rankValue];

  /// Bind [move] to ([node], [rankValue]), overwriting any previous choice.
  void record(BetNode node, int rankValue, BotMove move) {
    (_moves[node] ??= <int, BotMove>{})[rankValue] = move;
  }

  /// Fold every entry of [other] into this line (other wins on conflict).
  void merge(HumanLine other) {
    other._moves.forEach((node, byRank) {
      byRank.forEach((rank, move) => record(node, rank, move));
    });
  }

  bool get isEmpty => _moves.values.every((m) => m.isEmpty);

  /// Total number of captured (spot, card) decisions.
  int get count => _moves.values.fold(0, (sum, m) => sum + m.length);

  Map<String, dynamic> toJson() => {
        for (final e in _moves.entries)
          if (e.value.isNotEmpty)
            e.key.name: {
              for (final m in e.value.entries) '${m.key}': m.value.name,
            },
      };

  factory HumanLine.fromJson(Map<String, dynamic> json) {
    final moves = <BetNode, Map<int, BotMove>>{};
    json.forEach((nodeName, rankMap) {
      final node = _byName(BetNode.values, nodeName);
      if (node == null || rankMap is! Map) return;
      final inner = <int, BotMove>{};
      rankMap.forEach((rank, moveName) {
        final r = int.tryParse('$rank');
        final move = _byName(BotMove.values, '$moveName');
        if (r != null && move != null) inner[r] = move;
      });
      if (inner.isNotEmpty) moves[node] = inner;
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
