// A library file nothing imports is dead code that still costs maintenance:
// tests pin it and readers take it for live behaviour (SPEC 0252).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Orphans the Known Technical Debt section records as deliberate, each
/// waiting on its own wiring spec.
const _deliberateOrphans = {
  'lib/core/services/sync_engine.dart',
  'lib/core/services/research/proxy_research_service.dart',
  'lib/core/services/image_quality/image_quality_analyzer.dart',
  'lib/models/classification_verdict.dart',
};

void main() {
  test('no_library_file_is_orphaned', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .where((p) => p.endsWith('.dart') && !p.endsWith('.g.dart'))
        .toList();
    final sources = {for (final p in files) p: File(p).readAsStringSync()};

    final orphans = <String>[];
    for (final path in files) {
      if (path == 'lib/main.dart' || _deliberateOrphans.contains(path)) {
        continue;
      }
      final name = path.split('/').last;
      final imported = RegExp("['/]${RegExp.escape(name)}'");
      final used = sources.entries.any(
        (e) => e.key != path && imported.hasMatch(e.value),
      );
      if (!used) orphans.add(path);
    }

    expect(
      orphans,
      isEmpty,
      reason: 'delete the file, or record it as deliberate debt',
    );
  });
}
