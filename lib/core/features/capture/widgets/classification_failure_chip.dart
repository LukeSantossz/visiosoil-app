import 'package:visiosoil_app/core/services/classification_report.dart';

/// What the capture preview says when a classification fails with [cause], and
/// whether tapping it runs the same file again (SPEC 0105).
///
/// ADR 0015 leaves which causes earn a retry to the interface. Only a cause a
/// second run of the same file can change does: a timeout, an isolate that died
/// (an OS kill under memory pressure lands there), or a computation error
/// (memory exhaustion is caught there too). Every photograph-dependent cause is
/// a pure function of the decoded file, so it asks for another photograph and
/// says what to change. The switch is exhaustive, so a cause added to the enum
/// does not compile until it has copy.
({String label, bool retryable}) classificationFailureChip(
  ClassificationFailureCause cause,
) {
  const retry = 'Análise não terminou · tocar para tentar de novo';
  const unavailable = 'Análise indisponível nesta versão';
  return switch (cause) {
    ClassificationFailureCause.timeout ||
    ClassificationFailureCause.isolateFailure ||
    ClassificationFailureCause.computationError =>
      (label: retry, retryable: true),
    ClassificationFailureCause.sheetNotFound =>
      (label: 'Folha A4 não encontrada · tire outra foto', retryable: false),
    ClassificationFailureCause.sheetCropped =>
      (label: 'Folha cortada no quadro · tire outra foto', retryable: false),
    ClassificationFailureCause.soilRegionTooSmall =>
      (label: 'Pouco solo na folha · tire outra foto', retryable: false),
    ClassificationFailureCause.soilRegionOutsideFrame =>
      (label: 'Amostra fora da área lida · tire outra foto', retryable: false),
    ClassificationFailureCause.photographTooCoarse =>
      (label: 'Foto sem detalhe suficiente · tire outra foto', retryable: false),
    ClassificationFailureCause.imageMissing ||
    ClassificationFailureCause.imageUndecodable =>
      (label: 'Foto ilegível · tire outra foto', retryable: false),
    // One of its producers is a non-finite score from this photograph's
    // patches, which a new photograph can avoid and a rerun cannot.
    ClassificationFailureCause.outputInvalid => (
        label: 'Não foi possível analisar esta foto · tire outra foto',
        retryable: false,
      ),
    ClassificationFailureCause.contractMissing ||
    ClassificationFailureCause.contractMalformed ||
    ClassificationFailureCause.contractUnsupported =>
      (label: unavailable, retryable: false),
  };
}
