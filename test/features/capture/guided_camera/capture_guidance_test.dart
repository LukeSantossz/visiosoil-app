import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';

void main() {
  test('tilt_bands_name_the_sentence', () {
    void expectBand(double? tilt, GuidanceTone tone, String message) {
      final guidance = guidanceForTilt(tilt);
      expect(guidance.tone, tone, reason: '$tilt');
      expect(guidance.message, message, reason: '$tilt');
    }

    const level = 'Nivelado. Encaixe a folha no contorno.';
    const almost = 'Quase. Deixe o celular paralelo ao chão.';
    const tilted = 'Segure o celular paralelo ao chão, de cima.';
    expectBand(0, GuidanceTone.ready, level);
    expectBand(5, GuidanceTone.ready, level);
    expectBand(5.01, GuidanceTone.caution, almost);
    expectBand(12, GuidanceTone.caution, almost);
    expectBand(12.01, GuidanceTone.alert, tilted);
    expectBand(90, GuidanceTone.alert, tilted);
    expectBand(null, GuidanceTone.neutral, 'Encaixe a folha no contorno.');

    final icons = {
      for (final tilt in [0.0, 8.0, 20.0, null]) guidanceForTilt(tilt).icon,
    };
    expect(icons, hasLength(4), reason: 'each state carries its own icon');
  });
}
