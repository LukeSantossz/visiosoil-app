// Tests for [ImagePickerLostCaptureService]: how `image_picker`'s lost-data
// response maps to what the app does after Android killed it mid-capture
// (SPEC 0096).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/services/lost_capture_service.dart';

void main() {
  ImagePickerLostCaptureService serviceAnswering(
    LostDataResponse response, {
    bool android = true,
    void Function()? onAsk,
  }) =>
      ImagePickerLostCaptureService(
        retrieveLostData: () async {
          onAsk?.call();
          return response;
        },
        isAndroid: () => android,
      );

  test('retrieve_answers_none_for_an_empty_response', () async {
    final lost = await serviceAnswering(LostDataResponse.empty()).retrieve();

    expect(lost, isA<NoLostCapture>());
  });

  test('retrieve_answers_the_recovered_photographs_path', () async {
    final lost = await serviceAnswering(LostDataResponse(
      file: XFile('/cache/lost.jpg'),
      type: RetrieveType.image,
    )).retrieve();

    expect(
      lost,
      isA<RecoveredCapture>().having((c) => c.path, 'path', '/cache/lost.jpg'),
    );
  });

  test('retrieve_answers_unrecoverable_for_a_lost_data_exception', () async {
    final lost = await serviceAnswering(LostDataResponse(
      exception: PlatformException(code: 'no_available_camera'),
      type: RetrieveType.image,
    )).retrieve();

    expect(lost, isA<UnrecoverableCapture>());
  });

  test('retrieve_answers_none_off_android', () async {
    var asked = false;
    final lost = await serviceAnswering(
      LostDataResponse(file: XFile('/cache/lost.jpg'), type: RetrieveType.image),
      android: false,
      onAsk: () => asked = true,
    ).retrieve();

    expect(lost, isA<NoLostCapture>());
    expect(asked, isFalse);
  });
}
