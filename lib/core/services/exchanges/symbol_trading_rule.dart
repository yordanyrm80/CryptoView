import 'dart:math' as math;

/// Holds precision and lot size limits for a specific trading pair on an exchange.
class SymbolTradingRule {
  final String symbol;
  final double minSize;
  final double maxSize;
  final double stepSize; // baseIncrement / stepSize
  final double minPrice;
  final double maxPrice;
  final double tickSize; // priceIncrement / tickSize
  final double minFunds; // quoteMinSize / minNotional

  const SymbolTradingRule({
    required this.symbol,
    this.minSize = 0.000001,
    this.maxSize = 1000000000.0,
    this.stepSize = 0.000001,
    this.minPrice = 0.00000001,
    this.maxPrice = 1000000000.0,
    this.tickSize = 0.00000001,
    this.minFunds = 0.1,
  });

  /// Calculates number of decimal places from an increment step (e.g. 0.0001 -> 4)
  static int _getDecimals(double step) {
    if (step <= 0) return 6;
    final str = step.toStringAsFixed(8);
    if (!str.contains('.')) return 0;
    final decimals = str.split('.')[1].replaceAll(RegExp(r'0+$'), '');
    return decimals.length;
  }

  int get sizeDecimals => _getDecimals(stepSize);
  int get priceDecimals => _getDecimals(tickSize);

  /// Truncates size to step size without exceeding available balance
  double formatSize(double amount) {
    if (amount <= 0) return 0.0;
    if (stepSize <= 0) return amount;
    
    final decimals = sizeDecimals;
    final factor = math.pow(10, decimals).toDouble();
    // Floor to avoid rounding up beyond user balance
    final truncated = (amount * factor).floorToDouble() / factor;
    return double.parse(truncated.toStringAsFixed(decimals));
  }

  /// Formats price to exchange tick precision
  double formatPrice(double price) {
    if (price <= 0) return 0.0;
    if (tickSize <= 0) return price;

    final decimals = priceDecimals;
    return double.parse(price.toStringAsFixed(decimals));
  }

  /// Formats size as exact string for exchange API payload
  String formatSizeString(double amount) {
    final formatted = formatSize(amount);
    return formatted.toStringAsFixed(sizeDecimals);
  }

  /// Formats price as exact string for exchange API payload
  String formatPriceString(double price) {
    final formatted = formatPrice(price);
    return formatted.toStringAsFixed(priceDecimals);
  }

  /// Validates if an order size satisfies the minimum rule
  String? validateSize(double amount) {
    final formatted = formatSize(amount);
    if (formatted < minSize) {
      return 'La cantidad mínima es $minSize (ingresado: $formatted)';
    }
    if (formatted > maxSize) {
      return 'La cantidad máxima es $maxSize (ingresado: $formatted)';
    }
    return null;
  }

  /// Validates if the total funds satisfy min funds requirement
  String? validateFunds(double funds) {
    if (funds < minFunds) {
      return 'El monto mínimo de orden es \$$minFunds USDT';
    }
    return null;
  }
}
