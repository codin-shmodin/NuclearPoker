/// Card suits. Suits do NOT affect ranking in one-card poker (ties split the pot);
/// `isRed` is purely for display.
enum Suit {
  spades('♠', false),
  hearts('♥', true),
  diamonds('♦', true),
  clubs('♣', false);

  const Suit(this.symbol, this.isRed);

  final String symbol;
  final bool isRed;
}
