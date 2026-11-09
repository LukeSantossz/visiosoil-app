// The UI reads its sizes, spacing, radii, icons and colours from the theme's
// scales, and names a saved result one way (SPEC 0265). Each test lists the
// offending `file:line` and the token to use instead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A source file with its comments blanked out, keeping every offset and
/// line where it was.
class _Source {
  _Source(this.path, String raw) : text = _blankComments(raw) {
    final painter = RegExp(r'class \w+ extends CustomPainter');
    for (final match in painter.allMatches(text)) {
      final next = text.indexOf('\nclass ', match.end);
      _painters.add((match.start, next < 0 ? text.length : next));
    }
  }

  final String path;
  final String text;
  final _painters = <(int, int)>[];

  int lineOf(int offset) =>
      '\n'.allMatches(text.substring(0, offset)).length + 1;

  /// Whether [offset] falls inside a `CustomPainter`, whose illustration
  /// geometry and colours are out of the scales.
  bool inPainter(int offset) =>
      _painters.any((range) => offset >= range.$1 && offset < range.$2);

  String at(int offset) => '$path:${lineOf(offset)}';
}

/// Comments replaced by spaces, string literals left alone, so a `//` inside
/// a URL is not read as a comment.
String _blankComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"') {
      final triple = source.startsWith(c * 3, i) ? c * 3 : null;
      final close = triple ?? c;
      var j = i + close.length;
      while (j < source.length && !source.startsWith(close, j)) {
        if (source[j] == r'\') j++;
        if (triple == null && source[j] == '\n') break;
        j++;
      }
      j = (j + close.length).clamp(0, source.length);
      out.write(source.substring(i, j));
      i = j;
    } else if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      final stop = end < 0 ? source.length : end;
      out.write(' ' * (stop - i));
      i = stop;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? source.length : end + 2;
      out.write(source.substring(i, stop).replaceAll(RegExp(r'[^\n]'), ' '));
      i = stop;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

List<_Source> _lib() => [
  for (final file
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'),
          ))
    _Source(file.path.replaceAll('\\', '/'), file.readAsStringSync()),
];

/// The arguments of the call whose `(` is at [open], split at top-level
/// commas, each with its offset in the source.
List<(String, int)> _args(String text, int open) {
  final args = <(String, int)>[];
  var depth = 0;
  var start = open + 1;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        final last = text.substring(start, i);
        if (last.trim().isNotEmpty) args.add((last, start));
        return args;
      }
    } else if (c == ',' && depth == 1) {
      args.add((text.substring(start, i), start));
      start = i + 1;
    }
  }
  return args;
}

final _number = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])');

Iterable<double> _numbers(String expression) =>
    _number.allMatches(expression).map((m) => double.parse(m.group(1)!));

final _typeScale = {
  11.0,
  12.0,
  14.0,
  15.0,
  16.0,
  17.0,
  18.0,
  20.0,
  22.0,
  28.0,
  32.0,
  40.0,
};

void main() {
  test('font_sizes_are_on_the_type_scale', () {
    final offenders = <String>[];
    for (final source in _lib()) {
      // The shared image is drawn, not laid out as UI.
      if (source.path.endsWith('share_content_builder.dart')) continue;
      final text = source.text;
      for (final match in RegExp(r'\bfontSize:').allMatches(text)) {
        final end = text.indexOf(RegExp(r'[,)\n]'), match.end);
        for (final size in _numbers(text.substring(match.end, end))) {
          if (!_typeScale.contains(size)) {
            offenders.add('${source.at(match.start)} fontSize $size');
          }
        }
      }
      for (final match in RegExp(r'\bresized\(').allMatches(text)) {
        final args = _args(text, match.end - 1);
        if (args.length < 2 || args[1].$1.contains(':')) continue;
        for (final size in _numbers(args[1].$1)) {
          if (!_typeScale.contains(size)) {
            offenders.add('${source.at(match.start)} resized $size');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'snap to the nearest of $_typeScale (SPEC 0265)',
    );
  });

  test('spacing_is_on_the_4dp_grid', () {
    bool onGrid(double v) => v % 4 == 0 || v == 1 || v == 2;
    final offenders = <String>[];
    for (final source in _lib()) {
      final text = source.text;
      final insets = RegExp(
        r'\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB|fromSTEB)\(',
      );
      for (final match in insets.allMatches(text)) {
        if (source.inPainter(match.start)) continue;
        for (final (arg, offset) in _args(text, match.end - 1)) {
          for (final v in _numbers(arg.replaceFirst(RegExp(r'^\s*\w+:'), ''))) {
            if (!onGrid(v)) offenders.add('${source.at(offset)} EdgeInsets $v');
          }
        }
      }
      // A SizedBox with only a width or a height is a gap.
      for (final match in RegExp(r'\bSizedBox\(').allMatches(text)) {
        if (source.inPainter(match.start)) continue;
        final args = _args(text, match.end - 1);
        if (args.length != 1) continue;
        final gap = RegExp(
          r'^\s*(?:width|height):(.*)$',
          dotAll: true,
        ).firstMatch(args.single.$1);
        if (gap == null) continue;
        for (final v in _numbers(gap.group(1)!)) {
          if (!onGrid(v)) offenders.add('${source.at(match.start)} gap $v');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'use an AppSpacing token or a multiple of 4 (SPEC 0265)',
    );
  });

  test('radii_are_app_radius_tokens', () {
    final offenders = <String>[];
    for (final source in _lib()) {
      if (source.path.startsWith('lib/core/theme/')) continue;
      // The bar's end caps belong to a bar 3 or 4 dp tall.
      if (source.path.endsWith('confidence_bar.dart')) continue;
      final text = source.text;
      for (final match in RegExp(
        r'\b(?:Border)?Radius\.circular\(',
      ).allMatches(text)) {
        if (source.inPainter(match.start)) continue;
        final args = _args(text, match.end - 1);
        if (args.isEmpty || !args.first.$1.trim().startsWith('AppRadius.')) {
          offenders.add(
            '${source.at(match.start)} ${args.firstOrNull?.$1.trim()}',
          );
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use an AppRadius token (SPEC 0265)');
  });

  test('icons_are_lucide', () {
    final offenders = <String>[];
    for (final source in _lib()) {
      for (final match in RegExp(r'\bIcons\.\w+').allMatches(source.text)) {
        offenders.add('${source.at(match.start)} ${match.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'use the LucideIcons equivalent (SPEC 0265)',
    );
  });

  test('colour_literals_live_in_the_theme', () {
    const literalHomes = [
      'lib/core/theme/',
      'lib/core/widgets/google_g_logo.dart',
      'lib/core/widgets/google_sign_in_button.dart',
      'lib/core/services/share_content_builder.dart',
    ];
    // Drawn over a photograph or the brand colour.
    const chromeHomes = [
      ...literalHomes,
      'lib/core/features/capture/guided_camera/',
      'lib/core/features/capture/widgets/capture_image_preview.dart',
      'lib/core/features/preview/image_preview_screen.dart',
      'lib/core/features/splash/',
    ];
    bool under(String path, List<String> homes) =>
        homes.any((home) => path.startsWith(home));
    final offenders = <String>[];
    for (final source in _lib()) {
      final text = source.text;
      if (!under(source.path, literalHomes)) {
        final literal = RegExp(r'\bColor(?:\.from(?:ARGB|RGBO))?\(');
        for (final match in literal.allMatches(text)) {
          if (source.inPainter(match.start)) continue;
          offenders.add('${source.at(match.start)} ${match.group(0)}');
        }
      }
      if (!under(source.path, chromeHomes)) {
        for (final match in RegExp(
          r'\bColors\.(white|black)\w*',
        ).allMatches(text)) {
          if (source.inPainter(match.start)) continue;
          offenders.add('${source.at(match.start)} ${match.group(0)}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'read context.palette, or CameraColors on a photograph '
          '(SPEC 0265)',
    );
  });

  test('one_content_width', () {
    final offenders = <String>[];
    for (final source in _lib()) {
      if (source.path == 'lib/core/theme/app_layout.dart') continue;
      for (final match in RegExp(
        r'maxWidth:\s*560(?![\w.])',
      ).allMatches(source.text)) {
        offenders.add(source.at(match.start));
      }
    }
    expect(File('lib/core/theme/app_layout.dart').existsSync(), isTrue);
    expect(
      offenders,
      isEmpty,
      reason: 'wrap the content in ContentWidth (SPEC 0265)',
    );
  });

  test('a_saved_result_is_an_analise', () {
    final offenders = <String>[];
    final literal = RegExp(
      r"'(?:[^'\\\n]|\\.)*'|"
      r'"(?:[^"\\\n]|\\.)*"',
    );
    for (final source in _lib()) {
      for (final match in literal.allMatches(source.text)) {
        if (RegExp(
          'registro',
          caseSensitive: false,
        ).hasMatch(match.group(0)!)) {
          offenders.add('${source.at(match.start)} ${match.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'say "análise" (SPEC 0265)');
  });
}
