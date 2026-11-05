// The app bundles only the typeface its styles set (SPEC 0257). SPEC 0201
// moved every AppTypography style to InterVariable and retired Manrope, but
// left Manrope and the static Inter faces declared, so they shipped in every
// build with no style reading them, and Manrope with no license entry.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('every_bundled_font_family_is_the_one_the_styles_set', () {
    final families = RegExp(
      r'^\s*- family: (\S+)\s*$',
      multiLine: true,
    ).allMatches(pubspec).map((match) => match.group(1)!).toSet();

    expect(families, {AppTypography.bodyMedium.fontFamily});
  });

  test('every_font_file_is_declared_and_every_declared_file_exists', () {
    final declared = RegExp(
      r'asset: (assets/fonts/\S+\.(?:ttf|otf))',
    ).allMatches(pubspec).map((match) => match.group(1)!).toSet();
    final files = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll('\\', '/'))
        .where((path) => path.endsWith('.ttf') || path.endsWith('.otf'))
        .toSet();

    expect(files, declared);
  });
}
