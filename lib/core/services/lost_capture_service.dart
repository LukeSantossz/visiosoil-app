import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// What happened to a capture Android interrupted by killing the app while the
/// camera app was in front (SPEC 0096).
sealed class LostCapture {
  const LostCapture();
}

/// No capture was interrupted, or the platform never loses one this way.
final class NoLostCapture extends LostCapture {
  const NoLostCapture();
}

/// The camera app finished the capture after the app was killed, and the
/// photograph it took is at [path].
final class RecoveredCapture extends LostCapture {
  const RecoveredCapture(this.path);

  final String path;
}

/// A capture was interrupted, and the plugin kept only its error: there is no
/// photograph to recover.
final class UnrecoverableCapture extends LostCapture {
  const UnrecoverableCapture();
}

/// Reads the result of a capture the app was killed during.
///
/// The underlying store is read once: after a read, a second one answers
/// [NoLostCapture], so a caller can ask on every arrival home.
abstract class LostCaptureService {
  Future<LostCapture> retrieve();
}

/// [LostCaptureService] backed by `image_picker`'s `retrieveLostData`, which
/// only Android implements; every other platform answers [NoLostCapture]
/// without asking the plugin.
class ImagePickerLostCaptureService implements LostCaptureService {
  ImagePickerLostCaptureService({
    Future<LostDataResponse> Function()? retrieveLostData,
    bool Function()? isAndroid,
  })  : _retrieveLostData = retrieveLostData ?? ImagePicker().retrieveLostData,
        _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final Future<LostDataResponse> Function() _retrieveLostData;
  final bool Function() _isAndroid;

  @override
  Future<LostCapture> retrieve() async {
    if (!_isAndroid()) return const NoLostCapture();
    final response = await _retrieveLostData();
    if (response.isEmpty) return const NoLostCapture();
    final file = response.file;
    if (file != null) return RecoveredCapture(file.path);
    return const UnrecoverableCapture();
  }
}
