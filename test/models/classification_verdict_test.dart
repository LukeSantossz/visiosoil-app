import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/classification_verdict.dart';
import 'package:visiosoil_app/models/soil_texture_labels.dart';

/// Builds a descending distribution from probabilities, in canonical label
/// order, so each test reads as the five numbers the spec states.
List<ClassScore> distributionOf(List<double> probabilities) {
  final scores = <ClassScore>[
    for (var i = 0; i < probabilities.length; i++)
      ClassScore(
        label: SoilTextureLabels.ordered[i],
        probability: probabilities[i],
      ),
  ];
  scores.sort((a, b) => b.probability.compareTo(a.probability));
  return List.unmodifiable(scores);
}

void main() {
  group('ClassificationVerdict.fromDistribution', () {
    test('is conclusive on a clear leader', () {
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.94, 0.03, 0.01, 0.01, 0.01]),
        ),
        ClassificationVerdict.conclusive,
      );
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.60, 0.20, 0.10, 0.06, 0.04]),
        ),
        ClassificationVerdict.conclusive,
      );
    });

    test('is ambiguous on a narrow margin', () {
      // margin 0.05, pair 0.83.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.44, 0.39, 0.09, 0.05, 0.03]),
        ),
        ClassificationVerdict.ambiguous,
      );
    });

    test('is ambiguous when the pair holds the mass, despite top-1 below 0.50',
        () {
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.48, 0.44, 0.04, 0.02, 0.02]),
        ),
        ClassificationVerdict.ambiguous,
      );
    });

    test('is ambiguous when the leader has a close rival despite holding half',
        () {
      // The only case that exercises the margin conjunct of `conclusive`:
      // top-1 0.50 clears its share bar, and margin 0.05 is what rejects it.
      // Without this vector, deleting `margin >= conclusiveMarginThreshold`
      // from the conclusive branch passes the whole suite — which is the exact
      // defect that withdrew this rule's predecessor, recorded in the spec's
      // Alternatives Considered.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.50, 0.45, 0.02, 0.02, 0.01]),
        ),
        ClassificationVerdict.ambiguous,
      );
    });

    test('is insufficient when nothing leads', () {
      // margin 0.01, pair 0.49.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.25, 0.24, 0.22, 0.15, 0.14]),
        ),
        ClassificationVerdict.insufficient,
      );
    });

    test('is insufficient when the leader lacks a majority', () {
      // A wide margin does not rescue a leader holding less than half with no
      // rival: top-1 0.48 misses the 0.50 share bar, and margin 0.28 is too
      // wide to qualify as ambiguous, so neither band accepts it.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.48, 0.20, 0.14, 0.10, 0.08]),
        ),
        ClassificationVerdict.insufficient,
      );
    });

    test('does not depend on the caller having sorted the distribution', () {
      // Same five probabilities, shuffled. `InferenceService` sorts, but this
      // factory is public over any list and roadmap item 15 persists the
      // distribution, where row order is whatever the database returns.
      const unsorted = [
        ClassScore(label: 'Siltosa', probability: 0.09),
        ClassScore(label: 'Argilosa', probability: 0.44),
        ClassScore(label: 'Arenosa', probability: 0.03),
        ClassScore(label: 'Media', probability: 0.39),
        ClassScore(label: 'Muito Argilosa', probability: 0.05),
      ];

      expect(
        ClassificationVerdict.fromDistribution(unsorted),
        ClassificationVerdict.ambiguous,
      );
      expect(
        ClassificationVerdict.fromDistribution(unsorted),
        ClassificationVerdict.fromDistribution(
          distributionOf([0.03, 0.39, 0.09, 0.05, 0.44]),
        ),
      );
    });

    test('is notAnalysed when any score is non-finite', () {
      // The factory is public over any list, and roadmap item 15 will feed it
      // from the database rather than from the isolate that already rejects
      // these. A NaN would be skipped by the scan and an infinity would win it,
      // either way producing an assertive verdict over a distribution that
      // means nothing.
      expect(
        ClassificationVerdict.fromDistribution(const [
          ClassScore(label: 'Argilosa', probability: 0.60),
          ClassScore(label: 'Media', probability: double.nan),
          ClassScore(label: 'Arenosa', probability: 0.20),
        ]),
        ClassificationVerdict.notAnalysed,
      );
      expect(
        ClassificationVerdict.fromDistribution(const [
          ClassScore(label: 'Argilosa', probability: double.infinity),
          ClassScore(label: 'Media', probability: 0.20),
        ]),
        ClassificationVerdict.notAnalysed,
      );
    });

    test('is notAnalysed for an absent result', () {
      expect(
        ClassificationVerdict.fromDistribution(null),
        ClassificationVerdict.notAnalysed,
      );
    });

    test('is notAnalysed for an empty distribution', () {
      expect(
        ClassificationVerdict.fromDistribution(const []),
        ClassificationVerdict.notAnalysed,
      );
    });

    test('notAnalysed is distinct from insufficient', () {
      expect(
        ClassificationVerdict.notAnalysed,
        isNot(ClassificationVerdict.insufficient),
      );
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.25, 0.24, 0.22, 0.15, 0.14]),
        ),
        isNot(ClassificationVerdict.notAnalysed),
      );
      expect(
        ClassificationVerdict.fromDistribution(null),
        isNot(ClassificationVerdict.insufficient),
      );
    });

    test('is pure: the same distribution always yields the same verdict', () {
      final distribution = distributionOf([0.44, 0.39, 0.09, 0.05, 0.03]);
      final first = ClassificationVerdict.fromDistribution(distribution);
      for (var i = 0; i < 5; i++) {
        expect(ClassificationVerdict.fromDistribution(distribution), first);
      }
    });

    test('treats the conclusive top-share bound as inclusive', () {
      // Taken from the constant, not from a literal, so recalibrating the
      // threshold moves the case with it.
      final topShare = ClassificationVerdict.conclusiveTopShareThreshold;

      expect(
        ClassificationVerdict.fromDistribution([
          ClassScore(label: 'Argilosa', probability: topShare),
          ClassScore(label: 'Media', probability: 0.20),
          ClassScore(label: 'Siltosa', probability: 0.15),
          ClassScore(label: 'Muito Argilosa', probability: 0.10),
          ClassScore(label: 'Arenosa', probability: 0.05),
        ]),
        ClassificationVerdict.conclusive,
      );
    });

    // The margin bound's inclusiveness has no test, and cannot have one at the
    // conclusive branch. `>=` and `>` differ only at exact equality, and no
    // distribution with a top share at or above 0.50 can produce a margin
    // exactly equal to 0.15's double: doubles in [0.5, 1) are multiples of
    // 2^-53 and doubles in [0.25, 0.5) are multiples of 2^-54, so a difference
    // between them is a multiple of 2^-54, while 0.15's double is an odd
    // multiple of 2^-55. Four million randomly drawn pairs produced none. The
    // two operators are therefore interchangeable here, and a test claiming to
    // pin the bound would only be asserting that 0.50 - 0.35 rounds upward.
    // The bound that is both reachable and pinned is the pair share, below.

    test('treats the ambiguous pair bound as inclusive', () {
      // margin 0.01 is below 0.15; pair 0.65 is the inclusive lower bound.
      // `0.33 + 0.32` is bit-for-bit equal to the 0.65 literal, so this case
      // discriminates `>=` from `>` by arithmetic rather than by rounding
      // luck. That exactness is a property of these two operands and does not
      // transfer: `0.35 + 0.30` is 0.6499999999999999.
      expect(0.33 + 0.32, ClassificationVerdict.ambiguousPairShareThreshold);
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.33, 0.32, 0.13, 0.12, 0.10]),
        ),
        ClassificationVerdict.ambiguous,
      );
    });

    test('assigns every point around the thresholds to its intended band', () {
      // A grid either side of each bound, so recalibrating the three constants
      // is a change with coverage behind it rather than a silent reshaping of
      // the bands.
      const cases = <(double, double, ClassificationVerdict)>[
        (0.94, 0.03, ClassificationVerdict.conclusive),
        (0.60, 0.20, ClassificationVerdict.conclusive),
        (0.51, 0.30, ClassificationVerdict.conclusive),
        (0.50, 0.45, ClassificationVerdict.ambiguous),
        (0.49, 0.45, ClassificationVerdict.ambiguous),
        (0.48, 0.44, ClassificationVerdict.ambiguous),
        (0.44, 0.39, ClassificationVerdict.ambiguous),
        (0.34, 0.32, ClassificationVerdict.ambiguous),
        (0.49, 0.19, ClassificationVerdict.insufficient),
        (0.48, 0.20, ClassificationVerdict.insufficient),
        (0.33, 0.31, ClassificationVerdict.insufficient),
        (0.25, 0.24, ClassificationVerdict.insufficient),
      ];

      for (final (topShare, runnerUpShare, expected) in cases) {
        expect(
          ClassificationVerdict.fromDistribution([
            ClassScore(label: 'Argilosa', probability: topShare),
            ClassScore(label: 'Media', probability: runnerUpShare),
          ]),
          expected,
          reason: 'top1 $topShare, top2 $runnerUpShare',
        );
      }
    });

    test('a single-class distribution is judged on its own share', () {
      // No rival exists, so the margin is the whole of top-1. Stated because a
      // model with one output class is rejected elsewhere, and this type must
      // still be total rather than throw.
      expect(
        ClassificationVerdict.fromDistribution(
          const [ClassScore(label: 'Arenosa', probability: 0.90)],
        ),
        ClassificationVerdict.conclusive,
      );
      expect(
        ClassificationVerdict.fromDistribution(
          const [ClassScore(label: 'Arenosa', probability: 0.30)],
        ),
        ClassificationVerdict.insufficient,
      );
    });

    test('thresholds are exposed as named constants', () {
      expect(ClassificationVerdict.conclusiveMarginThreshold, 0.15);
      expect(ClassificationVerdict.conclusiveTopShareThreshold, 0.50);
      expect(ClassificationVerdict.ambiguousPairShareThreshold, 0.65);
    });
  });

  group('ClassScore', () {
    test('two scores with the same label and probability are equal', () {
      expect(
        const ClassScore(label: 'Media', probability: 0.4),
        const ClassScore(label: 'Media', probability: 0.4),
      );
    });

    test('scores differing in probability are not equal', () {
      expect(
        const ClassScore(label: 'Media', probability: 0.4),
        isNot(const ClassScore(label: 'Media', probability: 0.5)),
      );
    });
  });
}
