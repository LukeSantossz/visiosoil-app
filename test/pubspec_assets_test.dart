import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards what the app bundle carries (#292, SPEC 0101). A folder declared under
/// `assets:` ships everything in it, so a repository document left in one
/// reaches every phone. The contract is declared as a file; the corpus folder,
/// whose files are build products absent until a release, stays a folder and
/// must hold no document.
void main() {
  // The `flutter: assets:` entries, read the way the other pubspec tests read
  // the file: line by line, without a YAML dependency.
  List<String> declaredAssets() {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final start = lines.indexWhere((line) => line.trimRight() == '  assets:');
    expect(start, isNot(-1), reason: 'pubspec.yaml declares no assets');
    final entries = <String>[];
    for (final line in lines.skip(start + 1)) {
      final entry = RegExp(r'^    - (.+?)\s*$').firstMatch(line);
      if (entry == null) break;
      entries.add(entry.group(1)!);
    }
    return entries;
  }

  test('the_contract_is_declared_as_a_file', () {
    final assets = declaredAssets();

    expect(assets, contains('assets/models/spec.json'));
    expect(assets, isNot(contains('assets/models/')),
        reason: 'a declared folder ships every file in it');
  });

  test('no_declared_asset_folder_holds_a_document', () {
    for (final folder in declaredAssets().where((a) => a.endsWith('/'))) {
      for (final file in Directory(folder).listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        expect(name.toLowerCase().endsWith('.md'), isFalse,
            reason: '$folder ships the document $name to every phone');
        if (name == '.gitkeep') {
          expect(file.lengthSync(), 0,
              reason: '$folder$name is a placeholder that ships; keep it '
                  'empty');
        }
      }
    }
  });

  test('every_declared_asset_file_exists', () {
    for (final file in declaredAssets().where((a) => !a.endsWith('/'))) {
      expect(File(file).existsSync(), isTrue,
          reason: 'pubspec.yaml declares $file, and the build fails on a '
              'declared file that is missing');
    }
  });
}
