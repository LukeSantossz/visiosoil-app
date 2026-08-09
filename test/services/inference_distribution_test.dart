import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_texture_labels.dart';

void main() {
  // The distribution is built from the output tensor by a pure function, so
  // every criterion below runs against a synthetic tensor with no interpreter,
  // no isolate, and no model asset.
  List<ClassScore>? distributionOf(List<double> probabilities) =>
      InferenceService.buildDistribution(probabilities, probabilities.length);

  group('InferenceService.buildDistribution', () {
    test('contains every class, one entry per label', () {
      final distribution = distributionOf([0.1, 0.2, 0.3, 0.25, 0.15])!;

      expect(distribution, hasLength(SoilTextureLabels.ordered.length));
      expect(
        distribution.map((score) => score.label).toSet(),
        SoilTextureLabels.ordered.toSet(),
      );
    });

    test('is ordered by probability, highest first', () {
      final distribution = distributionOf([0.1, 0.2, 0.3, 0.25, 0.15])!;

      final probabilities =
          distribution.map((score) => score.probability).toList();
      expect(
        probabilities,
        [0.3, 0.25, 0.2, 0.15, 0.1],
      );
      expect(distribution.first.label, 'Siltosa');
    });

    test('breaks ties on canonical label order, and does so repeatably', () {
      // Media and Muito Argilosa both hold 0.3. Probability alone leaves their
      // order unspecified, and the order is user-visible.
      final first = distributionOf([0.1, 0.3, 0.2, 0.3, 0.1])!;
      final second = distributionOf([0.1, 0.3, 0.2, 0.3, 0.1])!;

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
      final distribution = distributionOf([0.05, 0.05, 0.30, 0.05, 0.05])!;

      expect(
        distribution.map((score) => score.probability).toList(),
        [0.30, 0.05, 0.05, 0.05, 0.05],
      );
      expect(
        distribution.fold<double>(0, (sum, score) => sum + score.probability),
        closeTo(0.5, 1e-9),
      );
    });

    test('returns null when the class count does not match the label list', () {
      expect(InferenceService.buildDistribution([0.5, 0.5], 2), isNull);
      expect(
        InferenceService.buildDistribution([0.2, 0.2, 0.2, 0.2, 0.1, 0.1], 6),
        isNull,
      );
    });

    test('rejects a tensor carrying a non-finite probability', () {
      // `double.compareTo` orders NaN above every number, so a NaN would sort
      // to the front and become the top-1 class with a NaN confidence. The
      // service rejects incompatible models rather than fabricating a
      // plausible-looking result; a malformed output is the same situation.
      expect(distributionOf([0.1, 0.2, double.nan, 0.3, 0.2]), isNull);
      expect(distributionOf([0.1, 0.2, double.infinity, 0.3, 0.2]), isNull);
      expect(
        distributionOf([0.1, 0.2, double.negativeInfinity, 0.3, 0.2]),
        isNull,
      );
    });

    test('returns an unmodifiable list', () {
      final distribution = distributionOf([0.1, 0.2, 0.3, 0.25, 0.15])!;

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
      // the label mapping is invisible at index 0.
      final distribution = distributionOf([0.05, 0.10, 0.15, 0.60, 0.10])!;
      final result = InferenceResult(
        textureClass: distribution.first.label,
        confidenceScore: distribution.first.probability,
        distribution: distribution,
      );

      expect(result.textureClass, 'Muito Argilosa');
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
