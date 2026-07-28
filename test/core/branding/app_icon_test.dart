// Guard for the committed launcher-icon source. This runs in CI and proves the
// artifact matches the design-system tile; it does NOT rasterize (the generator
// under test/tools/ does that locally). See spec 0025.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('app_icon.png is the design-system green tile carrying a white mark', () {
    final file = File('assets/branding/app_icon.png');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'regenerate with: '
          'GENERATE_ICONS=1 flutter test test/tools/generate_app_icon_test.dart',
    );

    final image = img.decodePng(file.readAsBytesSync());
    expect(image, isNotNull);
    expect(image!.width, 1024);
    expect(image.height, 1024);

    // A corner is bare tile: the design-system primary green #4A7C59.
    final corner = image.getPixel(4, 4);
    expect(corner.r, closeTo(0x4A, 3));
    expect(corner.g, closeTo(0x7C, 3));
    expect(corner.b, closeTo(0x59, 3));

    // The white mark occupies the tile centre; find at least one white pixel.
    var whiteFound = false;
    for (var y = 300; y < 724 && !whiteFound; y += 4) {
      for (var x = 300; x < 724; x += 4) {
        final p = image.getPixel(x, y);
        if (p.r > 230 && p.g > 230 && p.b > 230) {
          whiteFound = true;
          break;
        }
      }
    }
    expect(whiteFound, isTrue,
        reason: 'the white brand mark must be present in the tile centre');
  });
}
