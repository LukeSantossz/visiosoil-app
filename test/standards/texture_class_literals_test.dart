import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Since SPEC 0083 a classification is labelled with the shipped contract's
/// classes, so no file under `lib/` may name a texture class of its own. The
/// one exception is `soil_texture_colors.dart`, whose keys SPEC 0035 permits:
/// a colour is a design token and not model output, and `forClass` already
/// degrades for a label it does not know.
///
/// The names are the archive's five, not only the model's four, so a class the
/// model stops emitting cannot come back as a literal either.
const _classes = ['Arenosa', 'Media', 'Muito Argilosa', 'Argilosa', 'Siltosa'];

const _permitted = 'soil_texture_colors.dart';

void main() {
  test('no_texture_class_literal_in_lib', () {
    final literal = RegExp('''['"](${_classes.join('|')})['"]''');
    final offending = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.uri.pathSegments.last == _permitted) continue;
      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (literal.hasMatch(lines[index])) {
          offending.add('${entity.path}:${index + 1}');
        }
      }
    }
    expect(offending, isEmpty);
  });

  // Anti-vacuity: the pattern still finds a class literal and still ignores a
  // mention that is not a string, and the permitted file still names them.
  test('the texture class sweep is not vacuous', () {
    final literal = RegExp('''['"](${_classes.join('|')})['"]''');
    expect(
      literal.hasMatch("  'Muito Argilosa': AppColors.soilVeryClay,"),
      isTrue,
    );
    expect(literal.hasMatch('/// Arenosa is the sandiest class.'), isFalse);
    final permitted = File('lib/core/theme/$_permitted').readAsStringSync();
    expect(literal.hasMatch(permitted), isTrue);
  });
}
