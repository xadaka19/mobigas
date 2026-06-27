class IncomingOrder {
  final String orderId;
  final String customerName;
  final String customerArea;
  final String gasSize;
  final double amount;
  final double fee;
  final String distance;
  final String timeAgo;

  const IncomingOrder({
    required this.orderId,
    required this.customerName,
    required this.customerArea,
    required this.gasSize,
    required this.amount,
    required this.fee,
    required this.distance,
    required this.timeAgo,
  });
}

class CompletedOrder {
  final String orderId;
  final String customerName;
  final String gasSize;
  final double amount;
  final String date;

  const CompletedOrder({
    required this.orderId,
    required this.customerName,
    required this.gasSize,
    required this.amount,
    required this.date,
  });
}
