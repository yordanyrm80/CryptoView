class ChartData {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  const ChartData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartData &&
          date == other.date &&
          open == other.open &&
          high == other.high &&
          low == other.low &&
          close == other.close;

  @override
  int get hashCode => Object.hash(date, open, high, low, close);
}

class RulerData {
  final DateTime time;
  final double low;
  final double high;

  const RulerData(this.time, this.low, this.high);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulerData &&
          time == other.time &&
          low == other.low &&
          high == other.high;

  @override
  int get hashCode => Object.hash(time, low, high);
}
