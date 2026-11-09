import 'package:flutter/painting.dart';

/// The dark chrome drawn over a photograph: the guided camera, measured on
/// PNG 10 to 12 (SPEC 0211), and the full-screen preview. It is the same in
/// every theme, as the camera's black panel is, so it lives here rather than
/// in `AppPalette` (SPEC 0265).
abstract final class CameraColors {
  /// An icon drawn straight over a photograph, and the disc behind it.
  static const onPhoto = Color(0xFFFFFFFF);
  static const photoScrim = Color(0x73000000);

  /// Secondary text on the dark chrome.
  static const muted = Color(0xFFBDBDBD);

  /// The preview's row labels, a step lighter than [muted].
  static const label = Color(0xFFC8C8C8);

  /// The switch-camera disc.
  static const control = Color(0xFF262626);

  /// The guidance pill over the preview.
  static const pill = Color(0xD1000000);

  /// The flash drawn when the shutter fires.
  static const flash = Color(0x8CFFFFFF);

  /// The scrim under the top bar: black at 90 % fading out.
  static const scrimTop = Color(0xE6000000);
  static const scrimEnd = Color(0x00000000);

  /// The held shutter: its ring and its disc.
  static const heldRing = Color(0xFF666666);
  static const heldDisc = Color(0xFF555555);

  /// A quality chip's fill, its edge, and its edge when the reading is ready.
  static const chipFill = Color(0xFF1C1C1C);
  static const edge = Color(0xFF333333);
  static const readyEdge = Color(0xFF3C5E46);

  /// The refusal card: its fill, its text and its icon.
  static const alertCard = Color(0xFFFFF4E2);
  static const alertInk = Color(0xFF3A2A10);
  static const alertIcon = Color(0xFFB26A00);
}
