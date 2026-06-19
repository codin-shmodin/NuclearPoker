import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/players/bot_profile.dart';
import 'package:nuclear_poker/engine/players/range_bot.dart';
import 'package:nuclear_poker/features/headsup_trainer/human_line.dart';

void main() {
  group('HumanLine', () {
    test('starts empty and records a move per (position, spot, card)', () {
      final line = HumanLine();
      expect(line.isEmpty, isTrue);
      expect(line.count, 0);

      line.record(LinePosition.bb, BetNode.facingBet, 14, BotMove.call);
      expect(line.isEmpty, isFalse);
      expect(line.count, 1);
      expect(line.moveAt(LinePosition.bb, BetNode.facingBet, 14), BotMove.call);
      expect(line.moveAt(LinePosition.bb, BetNode.facingBet, 13), isNull);
      expect(line.moveAt(LinePosition.bb, BetNode.open, 14), isNull);
    });

    test('the same spot in the other position is independent', () {
      final line = HumanLine()
        ..record(LinePosition.btn, BetNode.facingBet, 14, BotMove.pot)
        ..record(LinePosition.bb, BetNode.facingBet, 14, BotMove.fold);
      // No information transfers between positions.
      expect(line.moveAt(LinePosition.btn, BetNode.facingBet, 14), BotMove.pot);
      expect(line.moveAt(LinePosition.bb, BetNode.facingBet, 14), BotMove.fold);
      expect(line.count, 2);
    });

    test('recording the same spot again overwrites', () {
      final line = HumanLine()
        ..record(LinePosition.btn, BetNode.open, 7, BotMove.check)
        ..record(LinePosition.btn, BetNode.open, 7, BotMove.pot);
      expect(line.count, 1);
      expect(line.moveAt(LinePosition.btn, BetNode.open, 7), BotMove.pot);
    });

    test('clear forgets just that cell', () {
      final line = HumanLine()
        ..record(LinePosition.btn, BetNode.open, 7, BotMove.pot)
        ..record(LinePosition.btn, BetNode.open, 8, BotMove.check)
        ..clear(LinePosition.btn, BetNode.open, 7);
      expect(line.moveAt(LinePosition.btn, BetNode.open, 7), isNull);
      expect(line.moveAt(LinePosition.btn, BetNode.open, 8), BotMove.check);
      expect(line.count, 1);
    });

    test('merge folds another line in, other wins conflicts', () {
      final base = HumanLine()
        ..record(LinePosition.btn, BetNode.open, 5, BotMove.check)
        ..record(LinePosition.bb, BetNode.facingBet, 14, BotMove.call);
      final hand = HumanLine()
        ..record(LinePosition.btn, BetNode.open, 5, BotMove.pot) // conflict
        ..record(LinePosition.bb, BetNode.checkedTo, 9, BotMove.pot); // new

      base.merge(hand);
      expect(base.moveAt(LinePosition.btn, BetNode.open, 5), BotMove.pot);
      expect(base.moveAt(LinePosition.bb, BetNode.facingBet, 14), BotMove.call);
      expect(base.moveAt(LinePosition.bb, BetNode.checkedTo, 9), BotMove.pot);
      expect(base.count, 3);
    });

    test('survives a JSON round-trip', () {
      final line = HumanLine()
        ..record(LinePosition.btn, BetNode.open, 14, BotMove.pot)
        ..record(LinePosition.btn, BetNode.facingRaise, 11, BotMove.fold)
        ..record(LinePosition.bb, BetNode.checkedTo, 2, BotMove.check);

      final restored = HumanLine.fromJson(line.toJson());
      expect(restored.count, line.count);
      expect(restored.moveAt(LinePosition.btn, BetNode.open, 14), BotMove.pot);
      expect(
          restored.moveAt(LinePosition.btn, BetNode.facingRaise, 11),
          BotMove.fold);
      expect(restored.moveAt(LinePosition.bb, BetNode.checkedTo, 2),
          BotMove.check);
    });

    test('fromJson ignores unknown positions, spots, cards and moves', () {
      final restored = HumanLine.fromJson(<String, dynamic>{
        'btn': {
          'open': {'14': 'pot', 'oops': 'call', '9': 'bogus'},
          'notANode': {'14': 'pot'},
        },
        'notAPosition': {
          'open': {'14': 'pot'},
        },
      });
      expect(restored.count, 1);
      expect(restored.moveAt(LinePosition.btn, BetNode.open, 14), BotMove.pot);
    });
  });
}
