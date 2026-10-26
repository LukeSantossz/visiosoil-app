/// Shared string constants used across more than one layer.
abstract final class AppStrings {
  /// Full confidence labels for the result badge (redesign v11 §3.14).
  static const String confidenceHigh = 'Confiança alta';
  static const String confidenceModerate = 'Confiança média';
  static const String confidenceLow = 'Confiança baixa';
  static const processingTitle = 'Analisando a amostra';
  static const processingModel = 'Comparando com o modelo no aparelho';
  static const processingEstimate = 'cerca de 5\u00A0s';
  static const textureDiagramDisclaimer =
      'Diagrama ilustrativo, com regiões aproximadas (USDA/SBCS). '
      'Mostra a classe, não a posição da amostra.';

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

  /// Settings' base theme selector (redesign v11 §3.11, SPEC 0184): segmented
  /// Sistema | Claro | Escuro. Modo Sol is a separate switch, below.
  static const String themeChoiceSystem = 'Sistema';
  static const String themeChoiceLight = 'Claro';
  static const String themeChoiceDark = 'Escuro';
  static const String themeChoiceSun = 'Modo Sol';

  /// Caption under the Modo Sol switch, describing what it does
  /// (redesign v11 §3.11, SPEC 0184).
  static const String themeChoiceCaption =
      'Alto contraste e letras maiores para o campo';

  /// The saved record laid out as the result screen (redesign v11 §3.6,
  /// SPEC 0194).
  static const String resultTitle = 'Resultado';
  static const String resultOverline = 'Classe textural (triângulo USDA)';
  static const String resultTabOverview = 'Visão geral';
  static const String resultTabManagement = 'Manejo';
  static const String resultTabDetails = 'Detalhes';
  static const String resultIntro =
      'O modelo estima a classe textural pela foto. A confiança indica o '
      'quanto ele está seguro dessa classe.';
  static const String resultAboutClassTitle = 'Sobre a classe';
  static const String resultAboutClassCaption = 'Referência geral';
  static const String resultAboutClassNote =
      'Faixa típica da classe, não medição desta amostra.';
  static const String resultSampleTitle = 'Amostra';
  static const String resultSampleUnlocated = 'Sem localização registrada';
  static const String resultSampleLocating = 'Localizando...';
  static const String resultLabNotice =
      'Estimativa por imagem. Para laudo, confirme com análise '
      'granulométrica em laboratório.';
  static const String resultCorrect = 'Corrigir';
  static const String resultManagementTips = 'Dicas de manejo';
  static const String resultErrorTitle = 'Não deu para classificar';
  static const String resultErrorWithoutCause =
      'Não foi possível analisar esta foto. Fotografe a amostra de novo, '
      'seguindo as dicas de captura.';
  static const String resultRetake = 'Fotografar de novo';

  /// The result's bookmark and the draft shown inside capture (SPEC 0196).
  static const String resultSave = 'Salvar';
  static const String resultSaved = 'Salvo';
  static const String resultRemoveSaved = 'Remover dos salvos';
  static const String resultRetry = 'Tentar de novo';

  /// The photo screen's title (redesign v11 §3.8, SPEC 0198).
  static const String photoTitle = 'Foto da amostra';
  static const String resultSavedSnackbar = 'Salvo no histórico';

  /// Perfil's "Sincronizar" while no sync backend exists (ADR 0022,
  /// SPEC 0204).
  static const String syncNotAvailable =
      'A sincronização com a conta ainda não está disponível. '
      'As análises seguem neste aparelho.';

  /// The gallery refused the saved photograph; the record stays (SPEC 0208).
  static const String gallerySaveFailed =
      'Não foi possível salvar a foto na galeria.';
  static const String resultDraftManagement =
      'Salve a análise para ver as dicas de manejo desta amostra.';
  static const String resultTriangleTitle = 'No triângulo textural';
  static String resultTriangleHighlight(String textureClass) =>
      'A região $textureClass está destacada.';
  static const String resultCaptureTips = 'Ver dicas de captura';
}
