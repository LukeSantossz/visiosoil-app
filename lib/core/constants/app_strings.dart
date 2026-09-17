/// Shared string constants used across more than one layer.
abstract final class AppStrings {
  /// Stored when a record has no usable address. Shared by the writers that
  /// persist it and by `SoilRecord.hasValidAddress` so the stored value and the
  /// validity check can never drift apart (the cause of the prior sentinel bug).
  static const String addressUnavailable = 'Localização não disponível';

  /// Shown when no corpus cell carried a disclaimer of its own — including the
  /// case where the app holds no corpus at all. The result contract requires a
  /// non-empty disclaimer on every result, so this is the floor rather than a
  /// decoration.
  ///
  /// `management_tips_section.dart` carries the same sentence as a literal
  /// fallback. Collapsing the two belongs to the UI/UX terminal, which owns that
  /// file; this constant is the writer's side.
  static const String managementTipsDisclaimer =
      'Dicas de manejo consultivas, baseadas em fontes públicas. '
      'Não substituem avaliação técnica presencial.';
}
