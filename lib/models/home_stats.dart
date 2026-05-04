/// Dados agregados para exibicao na HomeScreen.
class HomeStats {
  const HomeStats({
    required this.totalRecords,
    required this.distinctLocations,
    required this.averageConfidence,
  });

  /// Total de registros no banco.
  final int totalRecords;

  /// Quantidade de enderecos distintos.
  final int distinctLocations;

  /// Media de confianca (0.0 a 1.0) ou null se nenhum registro com score.
  final double? averageConfidence;

  /// Media formatada como porcentagem, ou '-' se nao disponivel.
  String get formattedConfidence => averageConfidence == null
      ? '-'
      : '${(averageConfidence! * 100).round()}%';
}
