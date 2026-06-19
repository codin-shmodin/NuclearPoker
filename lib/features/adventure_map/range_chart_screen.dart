import 'package:flutter/material.dart';

import '../../engine/cards/rank.dart';
import '../../engine/players/bot_profile.dart' show BetNode;
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
                              _SituationCard(situation: s, line: line),
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
  const _SituationCard({required this.situation, required this.line});

  final _Situation situation;
  final HumanLine line;

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
              const SizedBox(width: 34),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 34,
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
