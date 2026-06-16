import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// A small stack of chips representing a chip [amount]. Purely decorative — the
/// label carries the exact number.
class ChipStackWidget extends StatelessWidget {
  const ChipStackWidget({
    super.key,
    required this.amount,
    this.showLabel = true,
  });

  final int amount;
  final bool showLabel;

  Color _chipColor(int value) {
    if (value >= 50) return AppColors.chipBlack;
    if (value >= 20) return AppColors.chipGreen;
    if (value >= 10) return AppColors.chipBlue;
    return AppColors.chipRed;
  }

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    final chips = (amount / 8).ceil().clamp(1, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 14.0 + (chips - 1) * 3.5,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              for (var i = 0; i < chips; i++)
                Positioned(
                  bottom: i * 3.5,
                  child: _Chip(color: _chipColor(amount)),
                ),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            '$amount',
            style: const TextStyle(
              color: AppColors.goldBright,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
