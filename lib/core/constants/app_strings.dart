/// Shared string constants used across more than one layer.
abstract final class AppStrings {
  /// Stored when a record has no usable address. Shared by the writers that
  /// persist it and by `SoilRecord.hasValidAddress` so the stored value and the
  /// validity check can never drift apart (the cause of the prior sentinel bug).
  static const String addressUnavailable = 'Localização não disponível';
}
