import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../headsup_controller.dart';

/// EV hint bar: for each card the bot might hold, what potting is worth for us.
/// Colour runs bright red (lose a lot) → grey (≈0) → bright green (win a lot).
class EvBar extends StatelessWidget {
  const EvBar({super.key, required this.cells});

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
    final anyActive = cells.any((c) => c.active);
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.potPurple.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          const Text(
            'YOUR EV IF YOU POT',
            textAlign: TextAlign.center,
            style: TextStyle(
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
                      'Shown on\nyour turn',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rankLabel(true),
          const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2),
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
                    _chips(cell.chips),
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
