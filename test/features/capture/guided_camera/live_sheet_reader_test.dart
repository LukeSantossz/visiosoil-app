import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_sheet_reader.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

void main() {
  final live = liveContractOf(parseDescriptorContract(
    File('assets/models/spec.json').readAsStringSync(),
  ).contract!);
  final sheet = InferenceService.frameOf(img.decodeJpg(
    File('test/fixtures/sheet_photos/photo_160706.jpg').readAsBytesSync(),
  )!);

  test('the_isolate_reads_a_frame_and_echoes_its_generation', () async {
    final reader = await IsolateLiveSheetReader.spawn(live);
    addTearDown(reader.kill);
    final reply = reader.replies.first;
    reader.read(sheet, 7);
    final (:generation, :reading) = await reply.timeout(const Duration(seconds: 20));
    expect(generation, 7);
    expect(reading, isA<LiveSheetFound>());
    expect((reading as LiveSheetFound).discDiameterMm, closeTo(51.4, 0.5));
  });

  test('kill_ends_the_replies', () async {
    final reader = await IsolateLiveSheetReader.spawn(live);
    final done = reader.replies.toList();
    reader.kill();
    expect(await done.timeout(const Duration(seconds: 5)), isEmpty);
  });
}
