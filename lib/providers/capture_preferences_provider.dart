import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/gallery_saver.dart';

/// The three capture switches Configurações draws under "Câmera e análise"
/// (PNG 23, SPEC 0208), each read before the first frame like Vibração.
abstract final class CapturePreferenceKeys {
  static const frameGuide = 'capture.frameGuide';
  static const saveToGallery = 'capture.saveToGallery';
  static const recordLocation = 'capture.recordLocation';
}

/// The stored values, or each default when it was never stored or the store
/// cannot be read: guide on, gallery off, location on.
Future<({bool frameGuide, bool saveToGallery, bool recordLocation})>
restoreCapturePreferences() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    return (
      frameGuide: preferences.getBool(CapturePreferenceKeys.frameGuide) ?? true,
      saveToGallery:
          preferences.getBool(CapturePreferenceKeys.saveToGallery) ?? false,
      recordLocation:
          preferences.getBool(CapturePreferenceKeys.recordLocation) ?? true,
    );
  } catch (error) {
    developer.log('Capture preferences restore failed: $error', name: 'main');
    return (frameGuide: true, saveToGallery: false, recordLocation: true);
  }
}

final initialFrameGuideProvider = Provider<bool>((ref) => true);
final initialSaveToGalleryProvider = Provider<bool>((ref) => false);
final initialRecordLocationProvider = Provider<bool>((ref) => true);

/// Whether the guided camera draws its frame, banner and checks, and gates
/// the shutter on them.
final frameGuideProvider = NotifierProvider<CapturePreferenceController, bool>(
  () => CapturePreferenceController(
    CapturePreferenceKeys.frameGuide,
    initialFrameGuideProvider,
  ),
);

/// Whether saving a record also copies its stored photograph to the gallery.
final saveToGalleryProvider =
    NotifierProvider<CapturePreferenceController, bool>(
      () => CapturePreferenceController(
        CapturePreferenceKeys.saveToGallery,
        initialSaveToGalleryProvider,
      ),
    );

/// Whether a capture asks for the device's location.
final recordLocationProvider =
    NotifierProvider<CapturePreferenceController, bool>(
      () => CapturePreferenceController(
        CapturePreferenceKeys.recordLocation,
        initialRecordLocationProvider,
      ),
    );

class CapturePreferenceController extends Notifier<bool> {
  CapturePreferenceController(this._key, this._initial);

  final String _key;
  final Provider<bool> _initial;

  @override
  bool build() => ref.read(_initial);

  /// Applies [on] at once, then persists it.
  Future<void> select(bool on) async {
    state = on;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, on);
  }
}

/// Where a saved record's photograph goes when [saveToGalleryProvider] is on.
/// Overridden with a fake in tests.
final gallerySaverProvider = Provider<GallerySaver>(
  (ref) => const PluginGallerySaver(),
);
