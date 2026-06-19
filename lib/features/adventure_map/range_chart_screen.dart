import 'package:flutter/material.dart';

import '../../engine/cards/rank.dart';
import '../../engine/players/bot_profile.dart' show BetNode;
import '../../engine/players/range_bot.dart' show BotMove;
import '../../theme/app_colors.dart';
import '../headsup_trainer/headsup_controller.dart' show aggroVerb, aggroVerbCap;
import '../headsup_trainer/human_line.dart';
import 'level.dart';
import 'line_store.dart';

/// Your options at a "passive" node (open / checked to you): check, or open the
/// betting. At a "facing" node you can fold, call, or re-raise (pot).
const List<BotMove> _passiveMoves = [BotMove.check, BotMove.pot];
const List<BotMove> _facingMoves = [BotMove.fold, BotMove.call, BotMove.pot];

/// The facing node you reach when the action you're now answering is the
/// [depth]-th aggressive action of the round (1 = a bet, 2 = a 3-bet, 3+ = a
/// 4-bet+). Deeper than that all folds back into [BetNode.facingReraise] — the
/// engine only models three facing buckets, so the chart matches it.
BetNode _facingNode(int depth) => depth <= 1
    ? BetNode.facingBet
    : depth == 2
        ? BetNode.facingRaise
        : BetNode.facingReraise;

/// The editable view of the player's own *auto-range* — the saved [HumanLine]
/// the trainer auto-plays for them. Two sections (BTN / BB), keyed by position
/// so the two seats never share a range. Tap a square to cycle your action (it
/// auto-saves); tap an arrow to reveal (or hide) the opponent's next aggressive
/// action and your reply to it. Reached from the map's chart button, one tab per
/// level/opponent.
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

  /// Which optional (opponent-acts-again) steps the player has explicitly
  /// toggled on/off, keyed by "position_node_rank". When absent, a step defaults
  /// to *shown if it already holds a saved move* — so captured lines are visible
  /// without hunting, while empty BTN continuations stay collapsed by default.
  final Map<String, bool> _armed = {};

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

  String _armKey(LinePosition pos, BetNode node, int rv) =>
      '${pos.name}_${node.name}_$rv';

  bool _isArmed(LinePosition pos, BetNode node, int rv) =>
      _armed[_armKey(pos, node, rv)] ?? (_line.moveAt(pos, node, rv) != null);

  /// Toggle an opponent-action arrow. Turning it *off* discards the plan behind
  /// it (clears that reply) so what you see is what auto-play will do.
  void _toggleArm(LinePosition pos, BetNode node, int rv, bool armed) {
    setState(() {
      _armed[_armKey(pos, node, rv)] = !armed;
      if (armed) _line.clear(pos, node, rv);
    });
    if (armed) _save();
  }

  void _cycle(LinePosition pos, BetNode node, int rv, List<BotMove> moves) {
    final cycle = <BotMove?>[null, ...moves];
    final i = cycle.indexOf(_line.moveAt(pos, node, rv));
    final next = cycle[(i + 1) % cycle.length];
    setState(() {
      if (next == null) {
        _line.clear(pos, node, rv);
      } else {
        _line.record(pos, node, rv, next);
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
                            _sectionCard(LinePosition.btn),
                            _sectionCard(LinePosition.bb),
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

  Widget _sectionCard(LinePosition pos) {
    final ranks = Rank.values.reversed.toList(); // A → 2
    final isBtn = pos == LinePosition.btn;
    final linesPerRank = isBtn ? 1 : 2;
    final groupH = _kRowH * linesPerRank;
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
                ? 'You act first. Set your action, then tap an arrow to plan for '
                    "the opponent's reply."
                : 'The opponent acts first — two lines per hand: they check (top) '
                    'or they bet (bottom).',
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
                    Container(
                      width: 22,
                      height: groupH,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white10),
                        ),
                      ),
                      child: Text(
                        r.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
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
                        Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white10),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in _linesFor(pos, r.value))
                                SizedBox(
                                  height: _kRowH,
                                  child: Row(children: line),
                                ),
                            ],
                          ),
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

  List<List<Widget>> _linesFor(LinePosition pos, int rv) =>
      pos == LinePosition.btn
          ? [_btnLine(rv)]
          : [_bbCheckLine(rv), _bbBetLine(rv)];

  /// BTN row: your open square, then a *toggleable* arrow for the opponent's
  /// reply (off by default), then your facing square and any deeper re-raises.
  List<Widget> _btnLine(int rv) {
    const pos = LinePosition.btn;
    final out = <Widget>[_cell(pos, BetNode.open, rv, _passiveMoves, 1)];
    final youChecked = _line.moveAt(pos, BetNode.open, rv) == BotMove.check;
    // If you checked, they bet (1st aggressive action); if you bet, they 3-bet.
    final aggr = youChecked ? 1 : 2;
    final node = _facingNode(aggr);
    final armed = _isArmed(pos, node, rv);
    out.add(_ArrowTag(
      label: aggroVerb(aggr),
      color: AppColors.potPurple,
      filled: armed,
      onTap: () => _toggleArm(pos, node, rv, armed),
    ));
    if (armed) {
      out.add(_cell(pos, node, rv, _facingMoves, aggr + 1));
      _appendDeeper(out, pos, rv, node, aggr);
    }
    return out;
  }

  /// BB, opponent-checks line: a fixed (non-toggleable) check arrow, then your
  /// reply at [BetNode.checkedTo], then any deeper re-raises if you bet.
  List<Widget> _bbCheckLine(int rv) {
    const pos = LinePosition.bb;
    final out = <Widget>[
      const _ArrowTag(label: 'check', color: AppColors.chipBlue, filled: true),
      _cell(pos, BetNode.checkedTo, rv, _passiveMoves, 1),
    ];
    _appendDeeper(out, pos, rv, BetNode.checkedTo, 0);
    return out;
  }

  /// BB, opponent-bets line: a fixed (non-toggleable) bet arrow, then your reply
  /// at [BetNode.facingBet], then any deeper re-raises if you 3-bet.
  List<Widget> _bbBetLine(int rv) {
    const pos = LinePosition.bb;
    final out = <Widget>[
      _ArrowTag(label: aggroVerb(1), color: AppColors.potPurple, filled: true),
      _cell(pos, BetNode.facingBet, rv, _facingMoves, 2),
    ];
    _appendDeeper(out, pos, rv, BetNode.facingBet, 1);
    return out;
  }

  /// Append toggleable "opponent re-raises again" steps after your reply at
  /// ([node], [aggr]). The opponent only gets another action while you keep
  /// raising (your saved move is pot), so the chain stops where you call/fold or
  /// hit the deepest modelled node.
  void _appendDeeper(
      List<Widget> out, LinePosition pos, int rv, BetNode node, int aggr) {
    while (true) {
      if (_line.moveAt(pos, node, rv) != BotMove.pot) break; // you didn't raise
      if (node == BetNode.facingReraise) break; // deepest node we model
      final botDepth = aggr + 2; // your raise = aggr+1, their re-raise = aggr+2
      final nextNode = _facingNode(botDepth);
      final armed = _isArmed(pos, nextNode, rv);
      out.add(_ArrowTag(
        label: aggroVerb(botDepth),
        color: AppColors.potPurple,
        filled: armed,
        onTap: () => _toggleArm(pos, nextNode, rv, armed),
      ));
      if (!armed) break; // dim arrow — wait for the player to reveal it
      aggr = botDepth;
      node = nextNode;
      out.add(_cell(pos, node, rv, _facingMoves, aggr + 1));
    }
  }

  Widget _cell(
      LinePosition pos, BetNode node, int rv, List<BotMove> moves, int aggrIndex) {
    final move = _line.moveAt(pos, node, rv);
    return GestureDetector(
      onTap: () => _cycle(pos, node, rv, moves),
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
}

const double _kRowH = 38;

/// An opponent action between two of your squares, drawn as a traditional right-
/// pointing arrow — a wide rectangular shaft (the "neck", holding the action
/// name) capped by a triangular head a little wider than the shaft. A [filled]
/// arrow is part of the line (purple for a bet/3-bet, blue for a check); a
/// hollow one is a collapsed "they raise again" step you can tap to reveal.
/// [onTap] is null for the BB scenario arrows, which are fixed.
class _ArrowTag extends StatelessWidget {
  const _ArrowTag({
    required this.label,
    required this.color,
    required this.filled,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = filled ? color : Colors.transparent;
    final stroke = filled ? color : Colors.white.withValues(alpha: 0.30);
    final textColor =
        filled ? Colors.white : Colors.white.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: CustomPaint(
          painter: _ArrowPainter(fill: fill, stroke: stroke),
          child: Container(
            width: 52,
            height: 26,
            alignment: Alignment.center,
            padding: const EdgeInsets.only(right: 13), // room for the head
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                fontSize: 9,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a traditional right-pointing arrow: a wide rectangular shaft (the
/// "neck", which carries the label) ending in a triangular head whose base is a
/// little wider than the shaft.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    const head = 12.0; // triangle length
    final neckH = size.height * 0.60; // shaft thickness — a wide neck
    final headH = size.height * 0.92; // triangle base — a bit wider than the neck
    final bodyRight = size.width - head;
    final neckTop = (size.height - neckH) / 2;
    final neckBot = neckTop + neckH;
    final headTop = (size.height - headH) / 2;
    final headBot = headTop + headH;
    final path = Path()
      ..moveTo(0, neckTop)
      ..lineTo(bodyRight, neckTop)
      ..lineTo(bodyRight, headTop)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(bodyRight, headBot)
      ..lineTo(bodyRight, neckBot)
      ..lineTo(0, neckBot)
      ..close();
    if (fill.a != 0) {
      canvas.drawPath(path, Paint()..color = fill);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.fill != fill || old.stroke != stroke;
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
      return aggroVerbCap(aggrIndex).toUpperCase(); // BET / 3-BET / 4-BET …
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
              _swatch(AppColors.potPurple, 'Bet / 3-bet'),
              _swatch(AppColors.chipGreen, 'Call'),
              _swatch(AppColors.chipBlue, 'Check'),
              _swatch(AppColors.danger, 'Fold'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a square to set your action · tap an arrow to reveal or hide '
            'the opponent’s next bet',
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
