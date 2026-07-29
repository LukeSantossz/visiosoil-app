import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';

void main() {
  test('AppMotion durations mirror the design-system motion scale', () {
    expect(AppMotion.instant, const Duration(milliseconds: 90));
    expect(AppMotion.fast, const Duration(milliseconds: 140));
    expect(AppMotion.base, const Duration(milliseconds: 220));
    expect(AppMotion.slow, const Duration(milliseconds: 380));
    expect(AppMotion.reveal, const Duration(milliseconds: 640));
  });

  test('AppMotion easings mirror the design-system curves', () {
    expect(AppMotion.standard, const Cubic(0.2, 0, 0, 1));
    expect(AppMotion.emphasized, const Cubic(0.3, 0, 0.1, 1));
    expect(AppMotion.out, const Cubic(0, 0, 0.2, 1));
  });
}
