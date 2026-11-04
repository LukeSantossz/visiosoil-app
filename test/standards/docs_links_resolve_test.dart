// A relative link between documents breaks silently when a file moves or is
// deleted (SPEC 0253). Specs are the durable archive and keep the text they
// were approved with, so they are not scanned.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _readmes = ['README.md', 'ml/README.md', 'corpus/README.md'];

final _link = RegExp(r'\]\(([^)\s#]+)(?:#[^)]*)?\)');
final _scheme = RegExp(r'^[a-z]+:');

void main() {
  test('every_relative_doc_link_resolves', () {
    final documents = [
      ..._readmes.map(File.new),
      ...Directory('docs')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .where(
            (f) => !f.path.replaceAll('\\', '/').startsWith('docs/specs/'),
          ),
    ];

    var links = 0;
    final broken = <String>[];
    for (final document in documents) {
      for (final match in _link.allMatches(document.readAsStringSync())) {
        final target = match.group(1)!;
        if (_scheme.hasMatch(target)) continue;
        links++;
        final resolved = File(
          document.absolute.parent.uri.resolve(target).toFilePath(),
        );
        if (FileSystemEntity.typeSync(resolved.path) ==
            FileSystemEntityType.notFound) {
          broken.add('${document.path}: $target');
        }
      }
    }

    expect(links, greaterThan(0));
    expect(broken, isEmpty);
  });
}
