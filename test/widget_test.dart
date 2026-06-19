import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/features/adventure_map/adventure_map_screen.dart';
import 'package:nuclear_poker/features/adventure_map/level.dart';
import 'package:nuclear_poker/features/adventure_map/progress_store.dart';
import 'package:nuclear_poker/features/shop/shop_catalog.dart';
import 'package:nuclear_poker/features/shop/shop_store.dart';

/// In-memory store so the map widget test doesn't touch the prefs plugin.
class FakeProgressStore implements ProgressStore {
  FakeProgressStore([Set<int>? completed]) : _ids = {...?completed};
  final Set<int> _ids;

  @override
  Future<LevelProgress> load() async => LevelProgress({..._ids});

  @override
  Future<void> markComplete(int levelId) async => _ids.add(levelId);
}

/// In-memory shop store so the map widget test doesn't touch the prefs plugin.
class FakeShopStore implements ShopStore {
  FakeShopStore([ShopState? initial]) : _state = initial ?? const ShopState();
  ShopState _state;

  @override
  Future<ShopState> load() async => _state;

  @override
  Future<void> markOwned(String itemId) async =>
      _state = _state.withOwned(itemId);

  @override
  Future<void> recordAsafGrant() async => _state = _state.withAsafGrant();
}

String _nameOf(int index) => botProfileFor(kLevels[index].botProfileId).name;

void main() {
  testWidgets('map shows the title and the first opponent by name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AdventureMapScreen(
          store: FakeProgressStore(), shopStore: FakeShopStore()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('NUCLEAR'), findsOneWidget);
    // Nodes are labelled with the bot's name, not a fancy level title.
    expect(find.text(_nameOf(0)), findsOneWidget);
    expect(find.text(_nameOf(1)), findsOneWidget);
    expect(find.textContaining('0 / ${kLevels.length}'), findsOneWidget);
  });

  testWidgets('locked levels show a padlock; cleared ones show the reward',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AdventureMapScreen(
          store: FakeProgressStore({1}), shopStore: FakeShopStore()),
    ));
    await tester.pumpAndSettle();

    // Level 1 cleared → its coin reward shows on the node; later still locked.
    expect(find.text('🪙${kLevels.first.coinReward}'), findsWidgets);
    expect(find.byIcon(Icons.lock), findsWidgets);
    expect(find.textContaining('1 / ${kLevels.length}'), findsOneWidget);
  });

  testWidgets('tapping an unlocked node opens the trainer', (tester) async {
    // Own the whole shop so the (now shop-gated) toggle bar is populated.
    await tester.pumpWidget(MaterialApp(
      home: AdventureMapScreen(
        store: FakeProgressStore(),
        shopStore: FakeShopStore(ShopState.allOwned),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_nameOf(0)));
    await tester.pump(); // kick off navigation
    await tester.pump(const Duration(milliseconds: 300));

    // The trainer's toggle bar is unique to that screen.
    expect(find.text('Advanced'), findsOneWidget);

    // Let any bot-think timer fire so none is pending at teardown.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}
