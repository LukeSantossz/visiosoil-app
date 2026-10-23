// AppRadius tests including the new xs value (Redesign v11 §1.4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';

void main() {
  test('xs_is_4', () {
    expect(AppRadius.xs, 4.0);
  });

  test('sm_is_8', () {
    expect(AppRadius.sm, 8.0);
  });

  test('md_is_12', () {
    expect(AppRadius.md, 12.0);
  });

  test('lg_is_16', () {
    expect(AppRadius.lg, 16.0);
  });

  test('xl_is_24', () {
    expect(AppRadius.xl, 24.0);
  });

  test('pill_is_999', () {
    expect(AppRadius.pill, 999.0);
  });

  test('borderRadiusXs_uses_xs', () {
    expect(AppRadius.borderRadiusXs, BorderRadius.circular(AppRadius.xs));
  });

  test('all_prebuilt_border_radii_exist', () {
    expect(AppRadius.borderRadiusXs.topLeft.x, 4.0);
    expect(AppRadius.borderRadiusSm.topLeft.x, 8.0);
    expect(AppRadius.borderRadiusMd.topLeft.x, 12.0);
    expect(AppRadius.borderRadiusLg.topLeft.x, 16.0);
    expect(AppRadius.borderRadiusXl.topLeft.x, 24.0);
    expect(AppRadius.borderRadiusPill.topLeft.x, 999.0);
  });
}
