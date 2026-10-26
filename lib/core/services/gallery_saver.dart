import 'package:gal/gal.dart';

/// Copies a stored photograph into the device gallery (SPEC 0208).
abstract interface class GallerySaver {
  /// Throws when the gallery refuses the file or access is denied.
  Future<void> save(String imagePath);
}

/// [GallerySaver] backed by `gal`. It files no album: an album would need
/// read/write Photos access on iOS and legacy storage on Android 10, while a
/// plain save needs only add access (review of #438).
class PluginGallerySaver implements GallerySaver {
  const PluginGallerySaver();

  @override
  Future<void> save(String imagePath) async {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw StateError('gallery access denied');
    }
    await Gal.putImage(imagePath);
  }
}
