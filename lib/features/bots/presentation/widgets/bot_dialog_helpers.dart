String formatStrategyName(String raw) {
  switch (raw) {
    case 'BtcQuantumEvolutionRegimeStrategy':
      return 'Quantum Evolution Regime';
    default:
      return raw;
  }
}

List<double> parsePercentWeightsInput(String text, List<double> fallback) {
  final parts = text
      .split(',')
      .map((s) => double.tryParse(s.trim()))
      .whereType<double>()
      .where((n) => n > 0)
      .toList();
  if (parts.isEmpty) return fallback;
  final sum = parts.fold<double>(0.0, (a, b) => a + b);
  // Si el usuario escribe porcentajes (ej. 30, 25, 20, 15, 10 -> suma > 2), convertir a fraccion 0..1
  if (sum > 2.0) {
    return parts
        .map((n) => double.parse((n / 100.0).toStringAsFixed(4)))
        .toList();
  }
  return parts;
}

String formatPercentWeights(List<double> weights) {
  return weights
      .map((w) => (w <= 1.0 ? w * 100.0 : w)
          .toStringAsFixed(1)
          .replaceAll(RegExp(r'\.0$'), ''))
      .join(', ');
}
