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
      // rival: margin 0.28 clears the ambiguity bar, top-1 0.48 misses 0.50.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.48, 0.20, 0.14, 0.10, 0.08]),
        ),
        ClassificationVerdict.insufficient,
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

    test('sits exactly on the conclusive boundary', () {
      // margin 0.15 and top-1 0.50 are both inclusive lower bounds.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.50, 0.35, 0.07, 0.05, 0.03]),
        ),
        ClassificationVerdict.conclusive,
      );
    });

    test('sits exactly on the ambiguous pair boundary', () {
      // margin 0.01 is below 0.15; pair 0.65 is the inclusive lower bound.
      expect(
        ClassificationVerdict.fromDistribution(
          distributionOf([0.33, 0.32, 0.13, 0.12, 0.10]),
        ),
        ClassificationVerdict.ambiguous,
      );
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
