import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';

/// A camera's lens and sensor, as Camera2 reports them (SPEC 0238): the
/// focal length, and the long side of the active pixel array, in millimetres.
typedef CameraOptics = ({double focalLengthMm, double activeLongSideMm});

/// Where the guided camera reads the optics of the camera it opened.
abstract interface class CameraOpticsSource {
  /// The optics of the Camera2 camera [cameraId], or null when not known.
  Future<CameraOptics?> opticsOf(String cameraId);
}

/// [CameraOpticsSource] over `MainActivity`'s channel. Null off Android,
/// and for a missing plugin, a platform error or a malformed reply.
class PlatformCameraOpticsSource implements CameraOpticsSource {
  const PlatformCameraOpticsSource();

  static const _channel = MethodChannel('com.visiosoil.app/camera_optics');

  @override
  Future<CameraOptics?> opticsOf(String cameraId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'opticsOf',
        cameraId,
      );
      final focal = reply?['focalLengthMm'];
      final side = reply?['activeLongSideMm'];
      if (focal is! num || side is! num) return null;
      return (
        focalLengthMm: focal.toDouble(),
        activeLongSideMm: side.toDouble(),
      );
    } on Exception catch (e) {
      // A PlatformException or a MissingPluginException: no distance shown.
      developer.log(
        'Camera optics unavailable: $e',
        name: 'PlatformCameraOpticsSource',
      );
      return null;
    }
  }
}

/// The lens-to-sheet distance, in millimetres, of a sheet whose long side
/// spans [sheetLongSidePx] of a read frame [readLongSidePx] long, by the
/// thin-lens equation; null when any input is not positive.
///
/// It assumes the read frame spans the active array's long side.
double? estimatedDistanceMm({
  required CameraOptics optics,
  required double sheetLongSidePx,
  required double readLongSidePx,
}) {
  final f = optics.focalLengthMm;
  final side = optics.activeLongSideMm;
  if (!(f > 0 && side > 0 && sheetLongSidePx > 0 && readLongSidePx > 0)) {
    return null;
  }
  final imageMm = sheetLongSidePx * side / readLongSidePx;
  return f * (1 + sheetHeightMm / imageMm);
}
