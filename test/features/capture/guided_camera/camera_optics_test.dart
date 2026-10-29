import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_optics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const optics = (focalLengthMm: 5.6, activeLongSideMm: 7.3);

  test('distance_follows_the_thin_lens', () {
    final distance = estimatedDistanceMm(
      optics: optics,
      sheetLongSidePx: 700,
      readLongSidePx: 1024,
    );
    expect(distance, closeTo(339, 1));
  });

  test('distance_is_unknown_without_usable_optics', () {
    for (final value in [0.0, -1.0]) {
      expect(
        estimatedDistanceMm(
          optics: (focalLengthMm: value, activeLongSideMm: 7.3),
          sheetLongSidePx: 700,
          readLongSidePx: 1024,
        ),
        isNull,
      );
      expect(
        estimatedDistanceMm(
          optics: (focalLengthMm: 5.6, activeLongSideMm: value),
          sheetLongSidePx: 700,
          readLongSidePx: 1024,
        ),
        isNull,
      );
      expect(
        estimatedDistanceMm(
          optics: optics,
          sheetLongSidePx: value,
          readLongSidePx: 1024,
        ),
        isNull,
      );
      expect(
        estimatedDistanceMm(
          optics: optics,
          sheetLongSidePx: 700,
          readLongSidePx: value,
        ),
        isNull,
      );
    }
  });

  group('platform_optics_reads_the_channel_reply', () {
    const channel = MethodChannel('com.visiosoil.app/camera_optics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void answer(Future<Object?> Function(MethodCall call) handler) =>
        messenger.setMockMethodCallHandler(channel, handler);

    test('a reply gives the two numbers for the camera asked', () async {
      final calls = <MethodCall>[];
      answer((call) async {
        calls.add(call);
        return {'focalLengthMm': 5.6, 'activeLongSideMm': 7.3};
      });
      final read = await const PlatformCameraOpticsSource().opticsOf('0');
      expect(read, (focalLengthMm: 5.6, activeLongSideMm: 7.3));
      expect(calls.single.method, 'opticsOf');
      expect(calls.single.arguments, '0');
    });

    test('a null reply gives null', () async {
      answer((call) async => null);
      expect(await const PlatformCameraOpticsSource().opticsOf('0'), isNull);
    });

    test('a reply missing a number gives null', () async {
      answer((call) async => {'focalLengthMm': 5.6});
      expect(await const PlatformCameraOpticsSource().opticsOf('0'), isNull);
    });

    test('a platform error gives null', () async {
      answer((call) async => throw PlatformException(code: 'CAMERA'));
      expect(await const PlatformCameraOpticsSource().opticsOf('0'), isNull);
    });

    test('a missing plugin gives null', () async {
      expect(await const PlatformCameraOpticsSource().opticsOf('0'), isNull);
    });
  });
}
