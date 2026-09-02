import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/soil_texture_labels.dart';

void main() {
  group('SoilTextureLabels', () {
    // Named after SPEC 0046's `dart_label_list_matches_the_config_order`. The
    // literal is spelled out rather than derived so that a silent reordering,
    // or a class quietly returning, fails here.
    test('dart label list matches the config order', () {
      expect(
        SoilTextureLabels.ordered,
        ['Arenosa', 'Media', 'Muito Argilosa', 'Argilosa'],
      );
    });

    test('the label list carries no class the first model does not emit', () {
      expect(SoilTextureLabels.ordered, isNot(contains('Siltosa')));
    });

    // `same` rather than `equals` records the intent, but it is no stronger:
    // Dart canonicalises const lists, so an identical hand-rolled copy would
    // satisfy it too. The assertion that actually fails against a duplicate is
    // the ordering one below, which caught the real divergence.
    test('the inference label list resolves to the single source', () {
      expect(InferenceService.textureLabels, same(SoilTextureLabels.ordered));
    });

    // `SoilTextureColors.all` documented itself as "model output order" while
    // listing Siltosa before Media, contradicting InferenceService. Nothing
    // consumed the getter, so the contradiction was latent rather than a live
    // defect; this asserts it cannot come back.
    test('SoilTextureColors orders its entries by the single source', () {
      expect(
        SoilTextureColors.all.map((entry) => entry.key).toList(),
        SoilTextureLabels.ordered,
      );
    });

    test('colour map covers exactly the label list', () {
      expect(
        SoilTextureColors.all.map((entry) => entry.key).toSet(),
        SoilTextureLabels.ordered.toSet(),
      );
    });

    test('every label resolves to a colour other than the unknown fallback', () {
      for (final label in SoilTextureLabels.ordered) {
        expect(
          SoilTextureColors.forClass(label),
          isNot(SoilTextureColors.forClass('not a texture class')),
          reason: '$label has no colour of its own',
        );
      }
    });
  });
}
