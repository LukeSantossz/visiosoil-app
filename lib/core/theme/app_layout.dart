/// Layout limits shared by every screen (SPEC 0265).
abstract final class AppLayout {
  /// The widest a screen's content is laid out, centred on a wider screen
  /// (redesign v11 §10).
  static const double maxContentWidth = 560;

  /// The text scale from which a screen lays out for large text (SPEC 0121).
  static const double largeTextScale = 1.3;

  /// The available height under which a screen is short, which every phone
  /// in landscape is.
  static const double shortHeight = 480;
}
