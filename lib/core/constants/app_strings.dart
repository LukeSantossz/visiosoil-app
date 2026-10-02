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

  /// Shown on home when Android killed the app during a capture and the camera
  /// left only an error, so there is no photograph to recover (SPEC 0096).
  static const String lostCaptureUnrecoverable =
      'Não foi possível recuperar a foto da última captura. '
      'Capture a amostra novamente.';

  /// Settings' row that shares the local report of uncaught errors (SPEC 0110).
  static const String errorReportTitle = 'Relatório de erros';

  /// Under the row, whatever the report holds: nothing leaves the phone unless
  /// the user shares it.
  static const String errorReportPrivacy =
      'Fica só no aparelho. Nada é enviado sem você compartilhar.';

  /// The row's trailing text when the report holds no entry.
  static const String errorReportNothingToSend = 'Nada a enviar';

  /// The caption the share sheet carries with the report file.
  static const String errorReportShareCaption =
      'Relatório de erros do VisioSoil.';

  /// Shown when the report could not be shared. It names no cause, since the
  /// exception's text is not for the screen.
  static const String errorReportShareFailed =
      'Não foi possível compartilhar o relatório. Tente novamente.';
}
