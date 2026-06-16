/// The result of settling a hand: how many chips a given seat won.
class Payout {
  const Payout(this.seatIndex, this.amount);

  final int seatIndex;
  final int amount;
}
