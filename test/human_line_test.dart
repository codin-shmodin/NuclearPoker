import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/players/bot_profile.dart';
import 'package:nuclear_poker/engine/players/range_bot.dart';
import 'package:nuclear_poker/features/headsup_trainer/human_line.dart';

void main() {
  group('HumanLine', () {
    test('starts empty and records a move per (spot, card)', () {
      final line = HumanLine();
      expect(line.isEmpty, isTrue);
      expect(line.count, 0);

      line.record(BetNode.facingBet, 14, BotMove.call);
      expect(line.isEmpty, isFalse);
      expect(line.count, 1);
      expect(line.moveAt(BetNode.facingBet, 14), BotMove.call);
      expect(line.moveAt(BetNode.facingBet, 13), isNull);
      expect(line.moveAt(BetNode.open, 14), isNull);
    });

    test('recording the same spot again overwrites', () {
      final line = HumanLine()
        ..record(BetNode.open, 7, BotMove.check)
        ..record(BetNode.open, 7, BotMove.pot);
      expect(line.count, 1);
      expect(line.moveAt(BetNode.open, 7), BotMove.pot);
    });

    test('merge folds another line in, other wins conflicts', () {
      final base = HumanLine()
        ..record(BetNode.open, 5, BotMove.check)
        ..record(BetNode.facingBet, 14, BotMove.call);
      final hand = HumanLine()
        ..record(BetNode.open, 5, BotMove.pot) // conflict → other wins
        ..record(BetNode.checkedTo, 9, BotMove.pot); // new

      base.merge(hand);
      expect(base.moveAt(BetNode.open, 5), BotMove.pot);
      expect(base.moveAt(BetNode.facingBet, 14), BotMove.call);
      expect(base.moveAt(BetNode.checkedTo, 9), BotMove.pot);
      expect(base.count, 3);
    });

    test('survives a JSON round-trip', () {
      final line = HumanLine()
        ..record(BetNode.open, 14, BotMove.pot)
        ..record(BetNode.facingRaise, 11, BotMove.fold)
        ..record(BetNode.checkedTo, 2, BotMove.check);

      final restored = HumanLine.fromJson(line.toJson());
      expect(restored.count, line.count);
      expect(restored.moveAt(BetNode.open, 14), BotMove.pot);
      expect(restored.moveAt(BetNode.facingRaise, 11), BotMove.fold);
      expect(restored.moveAt(BetNode.checkedTo, 2), BotMove.check);
    });

    test('fromJson ignores unknown spots, cards and moves', () {
      final restored = HumanLine.fromJson(<String, dynamic>{
        'open': {'14': 'pot', 'oops': 'call', '9': 'bogus'},
        'notANode': {'14': 'pot'},
      });
      expect(restored.count, 1);
      expect(restored.moveAt(BetNode.open, 14), BotMove.pot);
    });
  });
}
