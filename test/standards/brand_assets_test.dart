// The README opens with a cover, and the brand files beside it are
// self-contained and draw the app's own mark (SPEC 0258). An SVG shown through
// <img> cannot load a font or a remote file, so text is outlined and nothing
// is linked; the mark is pinned to VisioSoilMarkGeometry so the README, the
// launcher and the app cannot show three different marks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

const _dir = 'docs/design/brand';
const _cover = '$_dir/readme-cover.svg';

const _svgs = [
  'readme-cover',
  'logo-mark',
  'app-tile',
  'logo-lockup-light',
  'logo-lockup-dark',
];

/// The PNG exported from each SVG is its viewBox times this factor.
const _pngScale = {
  'readme-cover': 2,
  'logo-mark': 512 / 48,
  'app-tile': 512 / 48,
  'logo-lockup-light': 4,
  'logo-lockup-dark': 4,
};

String _svg(String name) => File('$_dir/$name.svg').readAsStringSync();

List<double> _numbers(String element, List<String> attributes) => [
  for (final attribute in attributes)
    double.parse(
      RegExp('\\b$attribute="([-0-9.]+)"').firstMatch(element)!.group(1)!,
    ),
];

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  int word(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR', reason: path);
  return (width: word(16), height: word(20));
}

void main() {
  test('readme_opens_with_the_cover', () {
    final first = File('README.md').readAsLinesSync().first;
    final image = RegExp(r'<img src="([^"]+)" alt="([^"]*)"').firstMatch(first);

    expect(image, isNotNull, reason: first);
    expect(image!.group(1), _cover);
    expect(image.group(2)!.trim(), isNotEmpty);
    expect(File(_cover).existsSync(), isTrue);
  });

  test('brand_svgs_are_self_contained', () {
    for (final name in _svgs) {
      final svg = _svg(name);
      final links = RegExp(
        r'https?://[^"\s]+',
      ).allMatches(svg).map((match) => match.group(0)!);

      expect(svg, isNot(contains('<text')), reason: name);
      expect(svg, isNot(contains('<image')), reason: name);
      expect(svg, isNot(contains('@font-face')), reason: name);
      expect(
        links.where((link) => !link.startsWith('http://www.w3.org/')),
        isEmpty,
        reason: name,
      );
    }
  });

  test('every_brand_svg_draws_the_app_mark', () {
    const g = VisioSoilMarkGeometry.ringCentre;
    final expectedCircles = [
      [g.dx, g.dy, VisioSoilMarkGeometry.ringRadius],
      for (final grain in VisioSoilMarkGeometry.grains)
        [grain.centre.dx, grain.centre.dy, grain.radius],
    ];
    const start = VisioSoilMarkGeometry.handleStart;
    const end = VisioSoilMarkGeometry.handleEnd;

    for (final name in _svgs) {
      final mark = RegExp(
        r'<g id="mark"[^>]*>(.*?)</g>',
        dotAll: true,
      ).firstMatch(_svg(name));
      expect(mark, isNotNull, reason: name);

      final circles = RegExp(
        r'<circle[^>]*>',
      ).allMatches(mark!.group(1)!).map((m) => m.group(0)!).toList();
      final lines = RegExp(
        r'<line[^>]*>',
      ).allMatches(mark.group(1)!).map((m) => m.group(0)!).toList();

      expect(
        circles.map((c) => _numbers(c, ['cx', 'cy', 'r'])).toList(),
        expectedCircles,
        reason: name,
      );
      expect(_numbers(circles.first, ['stroke-width']), [
        VisioSoilMarkGeometry.ringStrokeWidth,
      ], reason: name);
      expect(lines, hasLength(1), reason: name);
      expect(_numbers(lines.single, ['x1', 'y1', 'x2', 'y2', 'stroke-width']), [
        start.dx,
        start.dy,
        end.dx,
        end.dy,
        VisioSoilMarkGeometry.handleStrokeWidth,
      ], reason: name);
      expect(lines.single, contains('stroke-linecap="round"'), reason: name);
    }
  });

  // The cover's text is outlined, so each text path names its words in
  // data-text, and the cover speaks the README's language (SPEC 0264).
  test('cover_text_is_english', () {
    const lines = [
      'Light',
      'Distance',
      'Focus',
      'Ready. Hold steady.',
      'VisioSoil',
      'Photograph a soil sample on an A4 sheet.',
      'The phone estimates its texture class.',
      'Guided camera',
      '4 texture classes',
      'Works offline',
    ];
    final paths = RegExp(
      r'<path fill="#[^"]*"[^>]*>',
    ).allMatches(_svg('readme-cover')).map((m) => m.group(0)!).toList();
    final texts = [
      for (final path in paths)
        RegExp(r'data-text="([^"]*)"').firstMatch(path)?.group(1),
    ];

    expect(texts, lines);
    for (final text in lines) {
      expect(text.codeUnits.every((unit) => unit < 128), isTrue, reason: text);
    }
  });

  test('every_brand_png_has_its_declared_size', () {
    for (final name in _svgs) {
      final viewBox = RegExp(
        r'viewBox="0 0 ([0-9.]+) ([0-9.]+)"',
      ).firstMatch(_svg(name))!;
      final factor = _pngScale[name]!;
      final size = _pngSize('$_dir/$name.png');

      expect(
        size.width,
        (double.parse(viewBox.group(1)!) * factor).round(),
        reason: name,
      );
      expect(
        size.height,
        (double.parse(viewBox.group(2)!) * factor).round(),
        reason: name,
      );
    }
  });
}
