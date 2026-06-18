import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../headsup_controller.dart';

/// Immediate-EV hint bar: for the action the player is hovering, the option-A
/// net chip result against each card the bot might hold — what you end the hand
/// with, for the lines that resolve when the bot answers. A "?" marks a card
/// where your action hands the decision back to you (we don't guess your next
/// move). Colour runs bright red (lose a lot) → grey (≈0) → bright green (win a
/// lot). Each cell is labelled by the kind of spot it is (Value / Fold Equity /
/// Paid Off / …). The footer shows the average across the known (non-"?") cards,
/// but hides it when most of the range answers aggressively (mostly "?").
class EvBar extends StatelessWidget {
  const EvBar({super.key, required this.title, required this.cells});

  final String title;
  final List<EvCell> cells;

  static const Color _grey = Color(0xFF5B6470);
  static const Color _green = Color(0xFF22C55E);
  static const Color _red = Color(0xFFEF4444);

  static Color colorFor(double ev) {
    if (ev >= 0) return Color.lerp(_grey, _green, ev.clamp(0, 1))!;
    return Color.lerp(_grey, _red, (-ev).clamp(0, 1))!;
  }

  @override
  Widget build(BuildContext context) {
    final active = cells.where((c) => c.active).toList();
    final anyActive = active.isNotEmpty;
    final known = active.where((c) => !c.unknown).toList();
    // When most of the bot's range answers aggressively (re-raise / bet), most
    // cells are "?", so the Avg would be the mean of a tiny leftover sample —
    // misleading. In that spot we hide it: there's no honest average to show.
    final mostlyAggressive =
        anyActive && (active.length - known.length) * 2 > active.length;
    final average = (known.isEmpty || mostlyAggressive)
        ? null
        : known.fold<int>(0, (sum, c) => sum + c.ev) / known.length;
    return Container(
      width: 116,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.potPurple.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: anyActive
                ? Column(
                    children: [
                      for (final cell in cells)
                        Expanded(child: _EvRow(cell: cell)),
                    ],
                  )
                : const Center(
                    child: Text(
                      'Hover an\naction',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
          ),
          if (anyActive && average != null) ...[
            const SizedBox(height: 4),
            Text(
              'Avg ${_signed(average)}',
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _signed(double v) {
    final s = v.abs() < 0.05 ? '0' : v.toStringAsFixed(1);
    return v > 0.05
        ? '+$s'
        : (v < -0.05 ? '-${v.abs().toStringAsFixed(1)}' : s);
  }
}

String _chips(int v) => v > 0 ? '+$v' : '$v';

class _EvRow extends StatelessWidget {
  const _EvRow({required this.cell});

  final EvCell cell;

  @override
  Widget build(BuildContext context) {
    if (!cell.active) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            _rankLabel(false),
            const SizedBox(width: 4),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (cell.unknown) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            _rankLabel(true),
            const SizedBox(width: 4),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: AppColors.potPurple.withValues(alpha: 0.5),
                  ),
                ),
                child: const Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rankLabel(true),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: cell.label,
              waitDuration: const Duration(milliseconds: 300),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: EvBar.colorFor(cell.color),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        cell.label,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _chips(cell.ev),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankLabel(bool active) => SizedBox(
        width: 16,
        child: Text(
          cell.rank.label,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: active ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      );
}
