import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../headsup_trainer/human_line.dart';

/// Persists the player's saved [HumanLine] per level. A thin interface mirroring
/// [ProgressStore] so the backing store can swap from on-device prefs to
/// Firebase/Firestore later without touching the trainer UI.
abstract class LineStore {
  Future<HumanLine> load(int levelId);

  Future<void> save(int levelId, HumanLine line);
}

/// The PoC store: one JSON blob per level in `shared_preferences`.
class SharedPrefsLineStore implements LineStore {
  static String _key(int levelId) => 'saved_line_$levelId';

  @override
  Future<HumanLine> load(int levelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(levelId));
    if (raw == null || raw.isEmpty) return HumanLine();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return HumanLine.fromJson(json);
    } catch (_) {
      return HumanLine(); // corrupt blob — start fresh rather than crash
    }
  }

  @override
  Future<void> save(int levelId, HumanLine line) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(levelId), jsonEncode(line.toJson()));
  }
}
