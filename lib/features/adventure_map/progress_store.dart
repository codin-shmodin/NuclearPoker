import 'package:shared_preferences/shared_preferences.dart';

import 'level.dart';

/// Persists [LevelProgress]. A thin interface so the backing store can swap from
/// on-device prefs to Firebase/Firestore later (per the stack doc's live-ops
/// plan) without touching the map UI.
abstract class ProgressStore {
  Future<LevelProgress> load();

  /// Record that [levelId] has been cleared. Idempotent.
  Future<void> markComplete(int levelId);
}

/// The PoC store: a small list of completed level ids in `shared_preferences`.
/// One on-device dependency, no backend, works on iOS/Android/web.
class SharedPrefsProgressStore implements ProgressStore {
  static const String _key = 'completed_level_ids';

  @override
  Future<LevelProgress> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final ids = <int>{for (final s in raw) int.parse(s)};
    return LevelProgress(ids);
  }

  @override
  Future<void> markComplete(int levelId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const <String>[]).toSet()
      ..add('$levelId');
    await prefs.setStringList(_key, ids.toList());
  }
}
