// The gallery copy asks only for what a plain save needs (SPEC 0208; review
// of #438): an album would need read/write Photos access on iOS and legacy
// storage on Android 10.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/gallery_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');

  test('plugin_saver_files_no_album', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'hasAccess' || call.method == 'requestAccess'
              ? true
              : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await const PluginGallerySaver().save('/tmp/sample.jpg');

    for (final call in calls) {
      final args = call.arguments as Map;
      if (args.containsKey('toAlbum')) {
        expect(args['toAlbum'], isFalse, reason: call.method);
      }
      if (call.method == 'putImage') expect(args['album'], isNull);
    }
    expect(calls.map((call) => call.method), contains('putImage'));
  });

  test('ios_declares_both_photo_descriptions', () {
    // iOS 13, the deployment target, asks for read/write access even for a
    // plain save, so both descriptions are needed.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSPhotoLibraryAddUsageDescription</key>'));
    expect(plist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
  });
}
