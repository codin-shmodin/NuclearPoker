import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../engine/players/bot_profile.dart';
import '../../theme/app_colors.dart';
import 'headsup_screen.dart';

/// Submenu shown after picking the Heads-Up Trainer: choose which transparent
/// opponent to face. Each profile plays — and narrates — a different style.
class BotPickerScreen extends StatelessWidget {
  const BotPickerScreen({super.key});

  static const Map<String, String> _emoji = {
    'rock': '🪨',
    'maniac': '🔥',
    'pro': '🎓',
  };

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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const Text(
                      'Pick your opponent',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'Each bot shows its full range — only its style differs.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
                for (var i = 0; i < BotProfile.all.length; i++) ...[
                  _BotCard(
                    profile: BotProfile.all[i],
                    emoji: _emoji[BotProfile.all[i].id] ?? '🤖',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HeadsUpScreen(profile: BotProfile.all[i]),
                      ),
                    ),
                  ).animate().fadeIn(delay: (100 * i).ms, duration: 400.ms).slideY(begin: 0.12),
                  const SizedBox(height: 14),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotCard extends StatelessWidget {
  const _BotCard({required this.profile, required this.emoji, required this.onTap});

  final BotProfile profile;
  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [AppColors.feltLight, AppColors.feltDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.blurb,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_fill, color: AppColors.goldBright, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
