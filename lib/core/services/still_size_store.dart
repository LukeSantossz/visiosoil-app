import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

/// The size, portrait, of the stills the guided camera takes on this device,
/// learned from the first one (SPEC 0166): the camera plugin reports the
/// preview's size but not the still's.
abstract interface class StillSizeStore {
  /// The stored size, or null when none is stored or it cannot be read.
  Future<Size?> read();

  Future<void> write(Size size);
}

/// [StillSizeStore] in `shared_preferences`, as `<width>x<height>`.
class SharedPreferencesStillSizeStore implements StillSizeStore {
  static const _key = 'guided_camera_still_size';

  @override
  Future<Size?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null) return null;
    final parts = value.split('x');
    if (parts.length != 2) return null;
    final width = double.tryParse(parts[0]);
    final height = double.tryParse(parts[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  @override
  Future<void> write(Size size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      '${size.width.round()}x${size.height.round()}',
    );
  }
}
