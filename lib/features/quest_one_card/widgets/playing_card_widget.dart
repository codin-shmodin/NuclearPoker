import 'package:flutter/material.dart';

import '../../../engine/cards/card.dart';
import '../../../theme/app_colors.dart';

/// Renders a single card, face-up or face-down, with a smooth flip when the
/// face is revealed at showdown.
class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget({
    super.key,
    required this.card,
    required this.faceUp,
    this.width = 58,
    this.highlight = false,
  });

  final PlayingCard? card;
  final bool faceUp;
  final double width;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.4;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) {
        final rotate = Tween(begin: 0.5, end: 0.0).animate(animation);
        return AnimatedBuilder(
          animation: rotate,
          child: child,
          builder: (context, ch) => Transform(
            transform: Matrix4.identity()..rotateY(rotate.value),
            alignment: Alignment.center,
            child: ch,
          ),
        );
      },
      child: (faceUp && card != null)
          ? _Face(card: card!, width: width, height: height, highlight: highlight)
          : _Back(width: width, height: height, key: const ValueKey('back')),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.card,
    required this.width,
    required this.height,
    required this.highlight,
  });

  final PlayingCard card;
  final double width;
  final double height;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = card.suit.isRed ? AppColors.cardRed : AppColors.cardBlack;
    return Container(
      key: ValueKey('face_${card.rank}_${card.suit}'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.cardFace,
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(
          color: highlight ? AppColors.gold : Colors.black12,
          width: highlight ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlight
                ? AppColors.gold.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.35),
            blurRadius: highlight ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Rank in the top-left and bottom-right corners (no suit there, so it
          // can't collide with the centre pip).
          Positioned(
            top: 3,
            left: 5,
            child: Text(
              card.rank.label,
              style: TextStyle(
                color: color,
                fontSize: width * 0.32,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          Positioned(
            bottom: 3,
            right: 5,
            child: Text(
              card.rank.label,
              style: TextStyle(
                color: color,
                fontSize: width * 0.32,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          // Suit pip in the centre.
          Center(
            child: Text(
              card.suit.symbol,
              style: TextStyle(color: color, fontSize: width * 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.14),
        gradient: const LinearGradient(
          colors: [AppColors.cardBackB, AppColors.cardBackA],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.goldDeep, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: width * 0.5,
          height: height * 0.6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(width * 0.08),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.6),
              width: 1.2,
            ),
          ),
          child: const Center(
            child: Text('☢', style: TextStyle(color: AppColors.gold, fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
