import 'package:flutter/material.dart';

import '../../engine/cards/rank.dart';
import '../../engine/players/bot_profile.dart' show BetNode, BotProfile;
import '../../engine/players/range_bot.dart' show BotMove;
import '../../theme/app_colors.dart';
import '../headsup_trainer/human_line.dart';
import 'level.dart';
import 'line_store.dart';

/// One situation column-group in the chart: a heading plus the chain of *your*
/// decision nodes along the "villain keeps raising" line (see
/// docs/expansion-plans.md §1).
class _Situation {
  const _Situation(this.title, this.nodes, this.columns);
  final String title;
  final List<BetNode> nodes;
  final List<String> columns; // short header per node
}

const List<_Situation> _situations = [
  _Situation('You open (button)',
      [BetNode.open, BetNode.facingRaise, BetNode.facingReraise],
      ['Open', 'v Raise', 'v 4-bet']),
  _Situation('Facing a bet',
      [BetNode.facingBet, BetNode.facingRaise, BetNode.facingReraise],
      ['v Bet', 'v Raise', 'v 4-bet']),
  _Situation('Checked to you', [BetNode.checkedTo], ['Check?']),
];

/// Read-only view of the player's *designed* range (their saved [HumanLine]) for
/// each level — the 13 ranks × 3 situations layout. Reached from the map's
/// chart button. Empty cells are spots you haven't captured yet.
class RangeChartScreen extends StatefulWidget {
  const RangeChartScreen({super.key, required this.lineStore});

  final LineStore lineStore;

  @override
  State<RangeChartScreen> createState() => _RangeChartScreenState();
}

class _RangeChartScreenState extends State<RangeChartScreen> {
  final Map<int, HumanLine> _lines = {};
  bool _loading = true;
  int _selected = kLevels.first.id;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    for (final level in kLevels) {
      _lines[level.id] = await widget.lineStore.load(level.id);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final line = _lines[_selected] ?? HumanLine();
    final level = kLevels.firstWhere((l) => l.id == _selected);
    final profile = botProfileFor(level.botProfileId);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundTop, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              _levelTabs(),
              const SizedBox(height: 4),
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.gold))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        child: Column(
                          children: [
                            for (final s in _situations)
                              _SituationCard(
                                  situation: s, line: line, profile: profile),
                            const _ChartLegend(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Text(
              'Your Ranges',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );

  Widget _levelTabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final level in kLevels) ...[
              _LevelTab(
                label: botProfileFor(level.botProfileId).name,
                selected: level.id == _selected,
                onTap: () => setState(() => _selected = level.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
}

class _LevelTab extends StatelessWidget {
  const _LevelTab(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.potPurpleDeep
              : AppColors.feltDark.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SituationCard extends StatelessWidget {
  const _SituationCard(
      {required this.situation, required this.line, required this.profile});

  final _Situation situation;
  final HumanLine line;
  final BotProfile profile;

  @override
  Widget build(BuildContext context) {
    final ranks = Rank.values.reversed.toList(); // A → 2
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.feltDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            situation.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.goldBright,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Column headers.
          Row(
            children: [
              const SizedBox(width: 37),
              for (final c in situation.columns)
                Expanded(
                  child: Text(
                    c,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final r in ranks) _rankRow(r),
        ],
      ),
    );
  }

  Widget _rankRow(Rank r) {
    final state = _lineState(profile, line, situation.nodes, r.value);
    // Subtle line-completeness wash behind the row: faint green when the line
    // is resolved (the bot has no further raise), faint amber when it's still
    // open (empty, or the bot could re-raise and we've saved no answer).
    final wash = switch (state) {
      _LineState.complete => AppColors.win.withValues(alpha: 0.10),
      _LineState.incomplete => const Color(0xFFE08A2B).withValues(alpha: 0.10),
      _LineState.empty => const Color(0xFFE08A2B).withValues(alpha: 0.05),
    };
    final edge = switch (state) {
      _LineState.complete => AppColors.win.withValues(alpha: 0.7),
      _LineState.incomplete => const Color(0xFFE08A2B).withValues(alpha: 0.7),
      _LineState.empty => Colors.white.withValues(alpha: 0.12),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: edge, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 2, 0, 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              r.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          for (final node in situation.nodes)
            Expanded(child: _cell(line.moveAt(node, r.value))),
        ],
      ),
    );
  }

  Widget _cell(BotMove? move) {
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: move == null
            ? Colors.white.withValues(alpha: 0.04)
            : _moveColor(move).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: move == null ? Colors.white12 : Colors.white24,
        ),
      ),
      child: Text(
        move == null ? '·' : _moveLabel(move),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: move == null ? AppColors.textMuted : Colors.white,
        ),
      ),
    );
  }
}

Color _moveColor(BotMove move) {
  switch (move) {
    case BotMove.pot:
      return AppColors.potPurple;
    case BotMove.call:
      return AppColors.chipGreen;
    case BotMove.check:
      return AppColors.chipBlue;
    case BotMove.fold:
      return AppColors.danger;
  }
}

String _moveLabel(BotMove move) {
  switch (move) {
    case BotMove.pot:
      return 'POT';
    case BotMove.call:
      return 'CALL';
    case BotMove.check:
      return 'CHECK';
    case BotMove.fold:
      return 'FOLD';
  }
}

/// How resolved a saved line is. [empty] = nothing saved here; [complete] = the
/// line ends with no further bot raise possible; [incomplete] = the bot could
/// still re-raise and we've saved no answer.
enum _LineState { empty, complete, incomplete }

/// The bot's facing node right after we pot/raise at one of *our* nodes — one
/// raise deeper down the ladder.
BetNode _botFacesAfterOurPot(BetNode ours) {
  switch (ours) {
    case BetNode.open:
    case BetNode.checkedTo:
      return BetNode.facingBet;
    case BetNode.facingBet:
      return BetNode.facingRaise;
    case BetNode.facingRaise:
    case BetNode.facingReraise:
      return BetNode.facingReraise;
  }
}

/// Whether the bot ever pots (raises) at [node] with any card.
bool _botEverPots(BotProfile profile, BetNode node) =>
    Rank.values.any((r) => profile.moveAt(node, r.value) == BotMove.pot);

/// Walk a situation's "bot keeps raising" chain for one card and report whether
/// the line is resolved. We pot → the bot may re-raise (faces a node one deeper):
/// if it never raises there the line is done; if it can, we need the next node
/// filled, else the line is still open.
_LineState _lineState(
    BotProfile profile, HumanLine line, List<BetNode> nodes, int v) {
  for (var i = 0; i < nodes.length; i++) {
    final move = line.moveAt(nodes[i], v);
    if (move == null) {
      return i == 0 ? _LineState.empty : _LineState.incomplete;
    }
    if (move != BotMove.pot) return _LineState.complete; // passive → resolved
    if (!_botEverPots(profile, _botFacesAfterOurPot(nodes[i]))) {
      return _LineState.complete; // our raise can't be re-raised
    }
    if (i == nodes.length - 1) return _LineState.incomplete; // no deeper column
  }
  return _LineState.incomplete;
}

/// The small key under the chart explaining the row washes.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _swatch(AppColors.win, 'Line resolved'),
          const SizedBox(width: 16),
          _swatch(const Color(0xFFE08A2B), 'Bot may re-raise / empty'),
        ],
      ),
    );
  }

  Widget _swatch(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
