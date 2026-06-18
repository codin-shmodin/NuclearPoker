import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../features/headsup_trainer/bot_picker_screen.dart';
import '../theme/app_colors.dart';

/// The lightweight "quest map" entry point. For now it holds one quest;
/// later quests slot in as more cards on this screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Row(
                  children: [
                    const Text('☢️', style: TextStyle(fontSize: 34)),
                    const SizedBox(width: 10),
                    Text(
                      'NUCLEAR',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: AppColors.goldBright,
                      ),
                    ),
                    Text(
                      'POKER',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.1),
                const SizedBox(height: 4),
                Text(
                  'Learn poker, one quest at a time.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 40),
                Text(
                  'YOUR QUESTS',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                _QuestCard(
                  number: 1,
                  title: 'Heads-Up Trainer',
                  subtitle: 'One card each, heads-up. The bot shows its range — '
                      'learn to read it and respond.',
                  unlocked: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BotPickerScreen(),
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(
                      begin: 0.15,
                    ),
                const SizedBox(height: 14),
                const _QuestCard(
                  number: 2,
                  title: 'Two Card Showdown',
                  subtitle: 'Coming soon.',
                  unlocked: false,
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool unlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unlocked ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: unlocked ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [AppColors.feltLight, AppColors.feltDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: unlocked ? AppColors.gold : AppColors.textMuted,
                width: 1.5,
              ),
              boxShadow: unlocked
                  ? [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.background.withValues(alpha: 0.45),
                    border: Border.all(color: AppColors.gold, width: 1.5),
                  ),
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.goldBright,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  unlocked ? Icons.play_circle_fill : Icons.lock,
                  color: unlocked ? AppColors.goldBright : AppColors.textMuted,
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
