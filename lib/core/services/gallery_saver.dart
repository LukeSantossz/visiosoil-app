import 'package:gal/gal.dart';

/// Copies a stored photograph into the device gallery (SPEC 0208).
abstract interface class GallerySaver {
  /// Throws when the gallery refuses the file or access is denied.
  Future<void> save(String imagePath);
}

/// [GallerySaver] backed by `gal`, filing photographs in a "VisioSoil" album.
class PluginGallerySaver implements GallerySaver {
  const PluginGallerySaver();

  static const album = 'VisioSoil';

  @override
  Future<void> save(String imagePath) async {
    if (!await Gal.hasAccess(toAlbum: true) &&
        !await Gal.requestAccess(toAlbum: true)) {
      throw StateError('gallery access denied');
    }
    await Gal.putImage(imagePath, album: album);
  }
}
