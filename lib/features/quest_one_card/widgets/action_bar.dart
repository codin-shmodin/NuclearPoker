import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../engine/game/game_view.dart';
import '../../../theme/app_colors.dart';

/// The human's controls. Shows Fold + (Check | Call) + Bet depending on the
/// legal actions in [view].
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.view,
    required this.onFold,
    required this.onCheck,
    required this.onCall,
    required this.onBet,
  });

  final GameView view;
  final VoidCallback onFold;
  final VoidCallback onCheck;
  final VoidCallback onCall;
  final VoidCallback onBet;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (view.toCall > 0)
        _ActionButton(
          label: 'Fold',
          color: AppColors.danger,
          onTap: onFold,
        ),
      if (view.canCheck)
        _ActionButton(
          label: 'Check',
          color: AppColors.chipBlue,
          onTap: onCheck,
        ),
      if (view.canCall)
        _ActionButton(
          label: 'Call ${view.toCall}',
          color: AppColors.chipGreen,
          onTap: onCall,
        ),
      if (view.canBet)
        _ActionButton(
          label: view.isOpen ? 'Bet ${view.raiseTarget}' : 'Raise to ${view.raiseTarget}',
          color: AppColors.goldDeep,
          highlight: true,
          onTap: onBet,
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: buttons[i]),
        ],
      ],
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.4, curve: Curves.easeOut);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: highlight ? AppColors.cardBlack : Colors.white,
        elevation: highlight ? 6 : 2,
      ),
      child: Text(label),
    );
  }
}
