import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/players/bot_profile.dart';
import 'package:nuclear_poker/engine/players/range_bot.dart';
import 'package:nuclear_poker/features/adventure_map/line_store.dart';
import 'package:nuclear_poker/features/adventure_map/range_chart_screen.dart';
import 'package:nuclear_poker/features/headsup_trainer/human_line.dart';

/// In-memory line store so the chart test doesn't touch the prefs plugin.
class FakeLineStore implements LineStore {
  FakeLineStore([Map<int, HumanLine>? data]) : _data = {...?data};
  final Map<int, HumanLine> _data;

  @override
  Future<HumanLine> load(int levelId) async => _data[levelId] ?? HumanLine();

  @override
  Future<void> save(int levelId, HumanLine line) async => _data[levelId] = line;
}

void main() {
  testWidgets('renders both positions with bet/3-bet terminology (no "raise")',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RangeChartScreen(lineStore: FakeLineStore())),
    );
    await tester.pumpAndSettle();

    expect(find.text('BTN'), findsOneWidget);
    expect(find.text('BB'), findsOneWidget);
    expect(find.text('Bet / 3-bet'), findsOneWidget);
    // The BB section's fixed scenario arrows are always present (one per rank).
    expect(find.text('CHECK'), findsWidgets);
    expect(find.text('BET'), findsWidgets);
    // The word "raise" is gone from the chart entirely.
    expect(find.text('RAISE'), findsNothing);
    // BTN's opponent-reply arrows are present but collapsed (off) by default.
    expect(find.text('3-BET'), findsWidgets);
  });

  testWidgets('a BB saved move renders on the BB side', (tester) async {
    final line = HumanLine()
      ..record(LinePosition.bb, BetNode.facingBet, 14, BotMove.call);
    await tester.pumpWidget(MaterialApp(
      home: RangeChartScreen(
        lineStore: FakeLineStore({1: line}),
      ),
    ));
    await tester.pumpAndSettle();

    // The BB "they bet" line for the ace now shows our CALL.
    expect(find.text('CALL'), findsWidgets);
  });
}
