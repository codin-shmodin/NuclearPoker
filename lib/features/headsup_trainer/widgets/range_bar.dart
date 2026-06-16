import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../headsup_controller.dart';

/// Vertical 2→A range scale showing the bot's range, coloured by what it will
/// do with each rank. Out-of-range ranks are dimmed; the bot's actual card is
/// outlined at the reveal.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.title, required this.cells});

  final String title;
  final List<RankCell> cells;

  static Color colorFor(RangeBucket b) {
    switch (b) {
      case RangeBucket.pot:
        return AppColors.potPurple;
      case RangeBucket.call:
        return AppColors.chipGreen;
      case RangeBucket.fold:
        return AppColors.danger;
      case RangeBucket.check:
        return AppColors.chipBlue;
      case RangeBucket.shown:
        return AppColors.gold;
    }
  }

  static String labelFor(RangeBucket b) {
    switch (b) {
      case RangeBucket.pot:
        return 'POT';
      case RangeBucket.call:
        return 'CALL';
      case RangeBucket.fold:
        return 'FOLD';
      case RangeBucket.check:
        return 'CHECK';
      case RangeBucket.shown:
        return 'RANGE';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Which buckets actually appear in the in-range cells (for the legend).
    final legend = <RangeBucket>{
      for (final c in cells)
        if (c.inRange) c.bucket,
    }.toList();

    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Column(
              children: [
                for (final cell in cells)
                  Expanded(child: _RankRow(cell: cell)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final b in legend) _LegendDot(bucket: b),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.cell});

  final RankCell cell;

  @override
  Widget build(BuildContext context) {
    final color = RangeBar.colorFor(cell.bucket);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              cell.rank.label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: cell.inRange ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: cell.inRange
                    ? color.withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(3),
                border: cell.isBotCard
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.bucket});

  final RangeBucket bucket;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: RangeBar.colorFor(bucket),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          RangeBar.labelFor(bucket),
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
