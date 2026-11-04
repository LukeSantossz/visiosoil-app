// Documentation is written in English (docs/agents/project.md). Product copy
// is pt-BR and may be quoted in a document, so quoted text, code and link
// text are removed before a line is read. A line that still holds three or
// more pt-BR function words is a pt-BR sentence (SPEC 0254). Specs are the
// durable archive, and a *.pt-BR.md file is a copy written for the people
// who take the photographs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _spans = [
  RegExp(r'`[^`]*`'),
  RegExp(r'"[^"\n]*"'),
  RegExp('“[^”]*”'),
  RegExp(r'\[[^\]]*\]\([^)]*\)'),
];

final _ptWords = RegExp(
  r'(?<!\p{L})(não|também|então|está|são|você|porque|quando|deve|fica|'
  r'ficam|pela|pelo|uma|isso|esse|essa|mesmo|ainda|sobre|depois|aqui|cada|'
  r'entre|nenhum|sem|com|para|foi|continua|ele|ela|seu|sua|nos|nas|pelos|'
  r'pelas)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);

void main() {
  test('docs_prose_is_english', () {
    final documents = Directory('docs')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.uri.pathSegments.skipWhile((s) => s != 'docs').join('/'))
        .where((p) => p.endsWith('.md'))
        .where((p) => !p.startsWith('docs/specs/'))
        .where((p) => !p.endsWith('.pt-BR.md'))
        .toList()
      ..sort();

    final offending = <String>[];
    for (final path in documents) {
      var fenced = false;
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('```')) {
          fenced = !fenced;
          continue;
        }
        if (fenced) continue;
        var prose = line;
        for (final span in _spans) {
          prose = prose.replaceAll(span, ' ');
        }
        if (_ptWords.allMatches(prose).length >= 3) {
          offending.add('$path:${i + 1}');
        }
      }
    }

    expect(offending, isEmpty);
  });
}
