import 'package:flutter/painting.dart' show Offset;

import '../../engine/players/bot_profile.dart';

/// One level = one heads-up match against one bot you have to bust. A [LevelDef]
/// is just a named pairing of (a [BotProfile], a little table config) plus the
/// map metadata (where the node sits on the path, its title, its reward). The
/// const [kLevels] list below is the single source of truth for the ladder —
/// adding a level is adding one entry. See docs/adventure-map.md.
class LevelDef {
  const LevelDef({
    required this.id,
    required this.title,
    required this.botProfileId,
    required this.rewardId,
    required this.mapPosition,
    this.startingStack = 50,
  });

  /// 1..N, also draw order along the path.
  final int id;

  /// Display name on the map node and in the trainer top bar.
  final String title;

  /// Resolves to a [BotProfile] via [botProfileFor].
  final String botProfileId;

  /// The particle/material dropped on first clear. Emoji placeholder for now;
  /// becomes a themed asset later (see docs/expansion-plans.md §2).
  final String rewardId;

  /// Normalized 0..1 position on the map background (x, y), where (0,0) is the
  /// top-left and (1,1) the bottom-right of the scrollable map canvas.
  final Offset mapPosition;

  /// Table config: the stack each player starts with.
  final int startingStack;
}

/// The single source of truth for the ladder. The first three levels reuse the
/// three existing bot personalities (Rocky → Vex → Sage), roughly in difficulty
/// order. Positions snake bottom→top so the path reads as a climb.
const List<LevelDef> kLevels = [
  LevelDef(
    id: 1,
    title: 'The Rookie',
    botProfileId: 'rock',
    rewardId: '⚛️',
    mapPosition: Offset(0.30, 0.13),
  ),
  LevelDef(
    id: 2,
    title: 'The Maniac',
    botProfileId: 'maniac',
    rewardId: '⚪',
    mapPosition: Offset(0.68, 0.46),
  ),
  LevelDef(
    id: 3,
    title: 'The Shark',
    botProfileId: 'pro',
    rewardId: '🔶',
    mapPosition: Offset(0.32, 0.80),
  ),
];

/// Resolve a [LevelDef.botProfileId] to its [BotProfile].
BotProfile botProfileFor(String id) =>
    BotProfile.all.firstWhere((p) => p.id == id);

/// The state of a level on the map.
enum LevelStatus { locked, unlocked, completed }

/// The player's progress: just the set of beaten level ids. Locked/unlocked is
/// *derived* from this (a level is unlocked if it's the first or the previous
/// one is completed), so there is one fact to persist and no way for the two to
/// disagree. Pure Dart — no Flutter, no I/O — so it's directly unit-testable.
class LevelProgress {
  const LevelProgress(this.completedLevelIds);

  const LevelProgress.empty() : completedLevelIds = const {};

  final Set<int> completedLevelIds;

  bool isCompleted(int id) => completedLevelIds.contains(id);

  /// A level is unlocked if it's the first (id <= 1) or the previous level is
  /// completed. Linear ladder for now; becomes a prerequisite map when levels
  /// branch (see docs/adventure-map.md §2.2).
  bool isUnlocked(int id) => id <= 1 || completedLevelIds.contains(id - 1);

  LevelStatus statusOf(int id) {
    if (isCompleted(id)) return LevelStatus.completed;
    if (isUnlocked(id)) return LevelStatus.unlocked;
    return LevelStatus.locked;
  }

  /// A copy with [id] added to the completed set.
  LevelProgress withCompleted(int id) =>
      LevelProgress({...completedLevelIds, id});
}
