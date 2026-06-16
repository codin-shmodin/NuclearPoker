import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/app.dart';

void main() {
  testWidgets('home screen shows the title and Quest 1', (tester) async {
    await tester.pumpWidget(const NuclearPokerApp());
    await tester.pumpAndSettle();
    expect(find.text('NUCLEAR'), findsOneWidget);
    expect(find.text('Heads-Up Trainer'), findsOneWidget);
  });
}
