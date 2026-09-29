import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/models/class_score.dart';

/// The shipped contract's classes, in its order. Written out here because a
/// test may name a class, and `lib/` may not (SPEC 0083).
const _labels = ['Arenosa', 'Media', 'Muito Argilosa', 'Argilosa'];

void main() {
  // The distribution is built from the contract's output by a pure function,
  // so every criterion below runs against a synthetic output with no isolate
  // and no contract asset.
  List<ClassScore>? distributionOf(List<double> probabilities) =>
      InferenceService.buildDistribution(probabilities, _labels);

  group('InferenceService.buildDistribution', () {
    test('contains every class, one entry per label', () {
      final distribution = distributionOf([0.1, 0.2, 0.3, 0.4])!;

      expect(distribution, hasLength(_labels.length));
      expect(
        distribution.map((score) => score.label).toSet(),
        _labels.toSet(),
      );
    });

    test('is ordered by probability, highest first', () {
      final distribution = distributionOf([0.1, 0.2, 0.3, 0.25])!;

      final probabilities =
          distribution.map((score) => score.probability).toList();
      expect(
        probabilities,
        [0.3, 0.25, 0.2, 0.1],
      );
      expect(distribution.first.label, 'Muito Argilosa');
    });

    test('breaks ties on canonical label order, and does so repeatably', () {
      // Media and Muito Argilosa both hold 0.3, at indices 1 and 2 of the
      // four-class list. Probability alone leaves their order unspecified, and
      // the order is user-visible.
      final first = distributionOf([0.1, 0.3, 0.3, 0.1])!;
      final second = distributionOf([0.1, 0.3, 0.3, 0.1])!;

      expect(
        first.take(2).map((score) => score.label).toList(),
        ['Media', 'Muito Argilosa'],
      );
      expect(
        second.map((score) => score.label).toList(),
        first.map((score) => score.label).toList(),
      );
    });

    test('passes probabilities through without renormalising', () {
      // These sum to 0.5. A renormalising implementation would return values
      // twice as large and every verdict threshold would silently shift.
      final distribution = distributionOf([0.05, 0.05, 0.30, 0.10])!;

      expect(
        distribution.map((score) => score.probability).toList(),
        [0.30, 0.10, 0.05, 0.05],
      );
      expect(
        distribution.fold<double>(0, (sum, score) => sum + score.probability),
        closeTo(0.5, 1e-9),
      );
    });

    test('returns null when the output does not carry one value per label', () {
      expect(InferenceService.buildDistribution([0.5, 0.5], _labels), isNull);
      expect(
        InferenceService.buildDistribution(
            [0.2, 0.2, 0.2, 0.2, 0.1, 0.1], _labels),
        isNull,
      );
      // Five values against four labels, the count this project emitted until
      // SPEC 0046: refused rather than silently relabelled.
      expect(
        InferenceService.buildDistribution([0.2, 0.2, 0.2, 0.2, 0.2], _labels),
        isNull,
      );
    });

    test('rejects a tensor carrying a non-finite probability', () {
      // `double.compareTo` orders NaN above every number, so a NaN would sort
      // to the front and become the top-1 class with a NaN confidence. The
      // service rejects incompatible models rather than fabricating a
      // plausible-looking result; a malformed output is the same situation.
      expect(distributionOf([0.1, 0.2, double.nan, 0.3]), isNull);
      expect(distributionOf([0.1, 0.2, double.infinity, 0.3]), isNull);
      expect(
        distributionOf([0.1, 0.2, double.negativeInfinity, 0.3]),
        isNull,
      );
    });

    test('rejects a tensor carrying a probability outside [0, 1]', () {
      // Unlike a NaN, these sort correctly, so nothing downstream signals that
      // anything is wrong: 1.1 becomes the top-1 class and is carried out as a
      // confidence of 1.1, which then clears every verdict threshold. A value
      // outside the probability domain is not a probability, whatever produced
      // it, so the tensor is refused rather than passed on.
      expect(distributionOf([0.1, 0.2, 1.1, 0.3]), isNull);
      expect(distributionOf([0.1, 0.2, -0.1, 0.3]), isNull);
    });

    test('accepts the closed bounds 0 and 1', () {
      // The domain is inclusive, and a one-hot tensor is what a confident
      // model is meant to emit. Rejecting it would make the guard above a
      // defect of its own.
      final distribution = distributionOf([0.0, 0.0, 1.0, 0.0])!;

      expect(distribution.first.label, 'Muito Argilosa');
      expect(distribution.first.probability, 1.0);
    });

    test('returns an unmodifiable list', () {
      final distribution = distributionOf([0.1, 0.2, 0.3, 0.25])!;

      expect(
        () => distribution.add(
          const ClassScore(label: 'Arenosa', probability: 1.0),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('InferenceResult', () {
    test('the first distribution entry matches the top-1 fields', () {
      // Argmax at index 3 — the case the spec names, because an off-by-one in
      // the label mapping is invisible at index 0. Index 3 is Argilosa in the
      // four-class list and was Muito Argilosa in the five-class one, which is
      // the reindexing SPEC 0046 records.
      final distribution = distributionOf([0.05, 0.10, 0.25, 0.60])!;
      final result = InferenceResult(
        textureClass: distribution.first.label,
        confidenceScore: distribution.first.probability,
        distribution: distribution,
      );

      expect(result.textureClass, 'Argilosa');
      expect(result.confidenceScore, 0.60);
    });

    test('defaults to an empty distribution', () {
      // Existing callers construct a result without one; the field is added
      // without forcing an edit to them.
      const result = InferenceResult(
        textureClass: 'Media',
        confidenceScore: 0.75,
      );

      expect(result.distribution, isEmpty);
    });
  });
}
