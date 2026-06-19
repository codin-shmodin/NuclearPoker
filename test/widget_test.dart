import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/features/adventure_map/adventure_map_screen.dart';
import 'package:nuclear_poker/features/adventure_map/level.dart';
import 'package:nuclear_poker/features/adventure_map/progress_store.dart';

/// In-memory store so the map widget test doesn't touch the prefs plugin.
class FakeProgressStore implements ProgressStore {
  FakeProgressStore([Set<int>? completed]) : _ids = {...?completed};
  final Set<int> _ids;

  @override
  Future<LevelProgress> load() async => LevelProgress({..._ids});

  @override
  Future<void> markComplete(int levelId) async => _ids.add(levelId);
}

void main() {
  testWidgets('map shows the title and the first level unlocked',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AdventureMapScreen(store: FakeProgressStore()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('NUCLEAR'), findsOneWidget);
    expect(find.text(kLevels.first.title), findsOneWidget);
    // Nothing cleared yet → progress reads 0 / N.
    expect(find.textContaining('0 / ${kLevels.length}'), findsOneWidget);
  });

  testWidgets('locked levels are not tappable; completed ones show the reward',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AdventureMapScreen(store: FakeProgressStore({1})),
    ));
    await tester.pumpAndSettle();

    // Level 1 cleared → its reward shows in the tray.
    expect(find.text(kLevels.first.rewardId), findsWidgets);
    expect(find.textContaining('1 / ${kLevels.length}'), findsOneWidget);
  });
}
