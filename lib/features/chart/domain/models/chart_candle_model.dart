class ChartData {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  ChartData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

class RulerData {
  final DateTime time;
  final double low;
  final double high;

  RulerData(this.time, this.low, this.high);
}
