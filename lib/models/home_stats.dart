/// Aggregated data for display on the HomeScreen.
class HomeStats {
  const HomeStats({
    required this.totalRecords,
    required this.distinctLocations,
    required this.averageConfidence,
  });

  /// Total number of records in the database.
  final int totalRecords;

  /// Number of distinct addresses.
  final int distinctLocations;

  /// Average confidence (0.0 to 1.0) or null if no record has a score.
  final double? averageConfidence;

  /// Average formatted as a percentage, or '-' if not available.
  String get formattedConfidence => averageConfidence == null
      ? '-'
      : '${(averageConfidence! * 100).round()}%';
}
