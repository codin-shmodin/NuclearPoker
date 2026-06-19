import 'package:flutter/material.dart';

import '../../engine/cards/rank.dart';
import '../../engine/players/bot_profile.dart' show BetNode;
import '../../engine/players/range_bot.dart' show BotMove;
import '../../theme/app_colors.dart';
import '../headsup_trainer/headsup_controller.dart' show aggroVerb, aggroVerbCap;
import '../headsup_trainer/human_line.dart';
import 'level.dart';
import 'line_store.dart';

/// Which position the row describes — the two halves of the auto-range chart.
enum _Section { btn, bb }

/// Your options at a "passive" node (open / checked to you): check, or open the
/// betting. At a "facing" node you can fold, call, or raise.
const List<BotMove> _passiveMoves = [BotMove.check, BotMove.pot];
const List<BotMove> _facingMoves = [BotMove.fold, BotMove.call, BotMove.pot];

/// The facing node you reach when the action you're now answering is the
/// [depth]-th aggressive action of the round (1 = a bet, 2 = a raise, 3+ = a
/// re-raise). Deeper than a re-raise all folds back into [BetNode.facingReraise].
BetNode _facingNode(int depth) => depth <= 1
    ? BetNode.facingBet
    : depth == 2
        ? BetNode.facingRaise
        : BetNode.facingReraise;

/// The editable view of the player's own *auto-range* — the saved [HumanLine]
/// the trainer auto-plays for them. Two sections (BTN / BB) of 13 rank rows.
/// Tap a square to cycle your action (it auto-saves); tap a dim arrow to add the
/// next "and the opponent raises again" step. Reached from the map's chart
/// button, one tab per level/opponent.
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

  /// How many *optional* (opponent-raises-again) steps the player has revealed
  /// for a given row, keyed by "section_rank_branch".
  final Map<String, int> _revealed = {};

  /// In the BB section, which branch a row currently shows: true = the opponent
  /// opened the betting (facing a bet), false = the opponent checked to you.
  final Map<String, bool> _bbBet = {};

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

  HumanLine get _line => _lines[_selected] ??= HumanLine();

  Future<void> _save() => widget.lineStore.save(_selected, _line);

  void _cycle(BetNode node, int rv, List<BotMove> moves) {
    final cycle = <BotMove?>[null, ...moves];
    final i = cycle.indexOf(_line.moveAt(node, rv));
    final next = cycle[(i + 1) % cycle.length];
    setState(() {
      if (next == null) {
        _line.clear(node, rv);
      } else {
        _line.record(node, rv, next);
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
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
                            _sectionCard(_Section.btn),
                            _sectionCard(_Section.bb),
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
              'Your Auto-Range',
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

  // ---- Section + rows -----------------------------------------------------

  Widget _sectionCard(_Section section) {
    final ranks = Rank.values.reversed.toList(); // A → 2
    final isBtn = section == _Section.btn;
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
            isBtn ? 'BTN' : 'BB',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.goldBright,
              letterSpacing: 1.0,
            ),
          ),
          Text(
            isBtn
                ? 'You act first — pick your action, then answer each raise.'
                : 'The opponent acts first — tap the arrow to set what they do.',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (final r in ranks)
                    SizedBox(
                      width: 22,
                      height: _kRowH,
                      child: Center(
                        child: Text(
                          r.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in ranks)
                        SizedBox(
                          height: _kRowH,
                          child: Row(children: _segments(section, r.value)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build one row left→right: your squares interleaved with opponent arrows,
  /// walking the betting line and stopping where it resolves (you call/fold, or
  /// the opponent's next raise hasn't been revealed yet).
  List<Widget> _segments(_Section section, int rv) {
    final out = <Widget>[];
    int aggr; // aggressive actions taken before the square about to be added
    BetNode node;

    if (section == _Section.btn) {
      out.add(_cell(BetNode.open, rv, _passiveMoves, 1));
      final youChecked = _line.moveAt(BetNode.open, rv) == BotMove.check;
      // The opponent always gets to act; this first arrow is always live.
      aggr = youChecked ? 1 : 2; // they bet (1) if you checked, else raise (2)
      out.add(_arrow(active: true, blue: false, label: aggroVerb(aggr)));
      node = _facingNode(aggr);
      out.add(_cell(node, rv, _facingMoves, aggr + 1));
    } else {
      final betKey = '$rv';
      final bet = _bbBet[betKey] ?? true;
      out.add(_arrow(
        active: bet,
        blue: !bet,
        label: bet ? aggroVerb(1) : 'check',
        onTap: () => setState(() => _bbBet[betKey] = !bet),
      ));
      if (bet) {
        aggr = 1;
        node = BetNode.facingBet;
        out.add(_cell(node, rv, _facingMoves, aggr + 1));
      } else {
        aggr = 0;
        node = BetNode.checkedTo;
        out.add(_cell(node, rv, _passiveMoves, aggr + 1));
      }
    }

    // Optional deeper steps: only while you keep raising (pot) does the
    // opponent get another raise to answer.
    final branch = section == _Section.bb ? (_bbBet['$rv'] ?? true) : true;
    final key = '${section.name}_${rv}_$branch';
    final revealed = _revealed[key] ?? 0;
    var optional = 0;
    while (true) {
      if (_line.moveAt(node, rv) != BotMove.pot) break; // you didn't raise
      if (node == BetNode.facingReraise) break; // deepest node we model
      final botDepth = aggr + 2; // your raise = aggr+1, their re-raise = aggr+2
      final nextNode = _facingNode(botDepth);
      final hasData = _line.moveAt(nextNode, rv) != null;
      final active = optional < revealed || hasData;
      final idx = optional;
      out.add(_arrow(
        active: active,
        blue: false,
        label: aggroVerb(botDepth),
        onTap: active ? null : () => setState(() => _revealed[key] = idx + 1),
      ));
      if (!active) break; // dim arrow — wait for the player to reveal it
      aggr = botDepth;
      node = nextNode;
      out.add(_cell(node, rv, _facingMoves, aggr + 1));
      optional++;
    }
    return out;
  }

  Widget _cell(BetNode node, int rv, List<BotMove> moves, int aggrIndex) {
    final move = _line.moveAt(node, rv);
    return GestureDetector(
      onTap: () => _cycle(node, rv, moves),
      child: Container(
        width: 52,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
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
          move == null ? '·' : _moveLabel(move, aggrIndex),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: move == null ? AppColors.textMuted : Colors.white,
          ),
        ),
      ),
    );
  }

  /// An opponent action between two of your squares. [active] arrows are filled
  /// (purple for a bet/raise, blue for a check); a dim arrow is an unrevealed
  /// "they raise again" step you can tap to add.
  Widget _arrow({
    required bool active,
    required bool blue,
    required String label,
    VoidCallback? onTap,
  }) {
    final color = !active
        ? Colors.white.withValues(alpha: 0.22)
        : blue
            ? AppColors.chipBlue
            : AppColors.potPurple;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: _kRowH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_right_alt, color: color, size: 22),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: 7.5,
                height: 1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const double _kRowH = 38;

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

String _moveLabel(BotMove move, int aggrIndex) {
  switch (move) {
    case BotMove.pot:
      return aggroVerbCap(aggrIndex).toUpperCase(); // BET / RAISE / 3-BET …
    case BotMove.call:
      return 'CALL';
    case BotMove.check:
      return 'CHECK';
    case BotMove.fold:
      return 'FOLD';
  }
}

/// The small key under the chart.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              _swatch(AppColors.potPurple, 'Bet / raise'),
              _swatch(AppColors.chipGreen, 'Call'),
              _swatch(AppColors.chipBlue, 'Check'),
              _swatch(AppColors.danger, 'Fold'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a square to set your action · tap a dim arrow to add the '
            'opponent’s next raise',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textMuted.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
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
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
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
