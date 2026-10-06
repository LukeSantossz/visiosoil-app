// Every failure cause gets a chip that says what happened and what helps
// (SPEC 0105). Only a cause a second run of the same file can fix offers that
// run; a photograph-dependent cause asks for another photograph.
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/widgets/classification_failure_chip.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';

void main() {
  const retryable = {
    ClassificationFailureCause.timeout,
    ClassificationFailureCause.isolateFailure,
    ClassificationFailureCause.computationError,
  };
  const buildIsWrong = {
    ClassificationFailureCause.contractMissing,
    ClassificationFailureCause.contractMalformed,
    ClassificationFailureCause.contractUnsupported,
  };

  test('every_cause_has_a_chip', () {
    for (final cause in ClassificationFailureCause.values) {
      final chip = classificationFailureChip(cause);

      expect(chip.label, isNotEmpty, reason: '$cause');
      expect(chip.retryable, retryable.contains(cause), reason: '$cause');
      if (retryable.contains(cause)) {
        expect(chip.label, contains('tentar de novo'), reason: '$cause');
      } else if (buildIsWrong.contains(cause)) {
        expect(chip.label, isNot(contains('tentar de novo')), reason: '$cause');
        expect(chip.label, isNot(contains('tire outra foto')),
            reason: '$cause');
      } else {
        expect(chip.label, contains('tire outra foto'), reason: '$cause');
      }
    }
  });

  // The reader's two ways to this cause, an empty sheet and a disc too small
  // for nine patches, share one remedy, and the chip names its size
  // (SPEC 0142).
  test('the_small_soil_chip_names_the_size', () {
    final chip =
        classificationFailureChip(ClassificationFailureCause.soilRegionTooSmall);

    expect(
      chip.label,
      'Pouco solo na folha · espalhe um círculo de 8 a 10 cm e tire outra foto',
    );
    expect(chip.retryable, isFalse);
  });
}
