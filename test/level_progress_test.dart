import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/features/adventure_map/level.dart';

void main() {
  group('LevelProgress', () {
    test('empty: only the first level is unlocked', () {
      const p = LevelProgress.empty();
      expect(p.statusOf(1), LevelStatus.unlocked);
      expect(p.statusOf(2), LevelStatus.locked);
      expect(p.statusOf(3), LevelStatus.locked);
    });

    test('completing a level unlocks the next and stays completed', () {
      const p = LevelProgress({1});
      expect(p.statusOf(1), LevelStatus.completed);
      expect(p.statusOf(2), LevelStatus.unlocked);
      expect(p.statusOf(3), LevelStatus.locked);
    });

    test('withCompleted derives unlocks without storing them', () {
      final p = const LevelProgress.empty().withCompleted(1).withCompleted(2);
      expect(p.completedLevelIds, {1, 2});
      expect(p.statusOf(2), LevelStatus.completed);
      expect(p.statusOf(3), LevelStatus.unlocked);
    });
  });

  group('kLevels', () {
    test('ids are sequential from 1 and bot profiles resolve', () {
      for (var i = 0; i < kLevels.length; i++) {
        expect(kLevels[i].id, i + 1);
        // Throws if the profile id is unknown.
        expect(botProfileFor(kLevels[i].botProfileId).id,
            kLevels[i].botProfileId);
      }
    });
  });
}
