/// Formatting utilities for the app.
///
/// Centralizes formatting functions to avoid duplication (DRY).
class Formatters {
  Formatters._();

  /// [n] followed by [singular] when it is exactly one and by [plural]
  /// otherwise, zero included, as pt-BR counts (SPEC 0223).
  static String count(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';

  /// Formats an ISO 8601 timestamp for display.
  ///
  /// Example: "2026-04-01T14:30:00" -> "01/04/2026 às 14:30"
  static String timestamp(String isoTimestamp) {
    return _formatTimestamp(isoTimestamp, ' às ');
  }

  /// Formats an ISO 8601 timestamp for compact display (without the "às" connector).
  ///
  /// Example: "2026-04-01T14:30:00" -> "01/04/2026 14:30"
  static String timestampCompact(String isoTimestamp) {
    return _formatTimestamp(isoTimestamp, ' ');
  }

  /// Formats an ISO 8601 timestamp for the result screen's date chip
  /// (redesign v11 §3.6).
  ///
  /// Example: "2026-10-22T10:42:00" -> "22/10/2026 · 10:42"
  static String timestampDotted(String isoTimestamp) {
    return _formatTimestamp(isoTimestamp, ' · ');
  }

  /// Parses an ISO 8601 timestamp and formats it as `dd/MM/yyyy` and `HH:mm`
  /// joined by [connector].
  ///
  /// Returns [isoTimestamp] unchanged when it cannot be parsed.
  static String _formatTimestamp(String isoTimestamp, String connector) {
    try {
      final date = DateTime.parse(isoTimestamp);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$day/$month/${date.year}$connector$hour:$minute';
    } catch (_) {
      return isoTimestamp;
    }
  }

  /// Formats GPS coordinates for display.
  ///
  /// Example: (-23.550520, -46.633308) -> "-23.550520, -46.633308"
  static String coordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  /// GPS coordinates as the photo screen shows them (PNG 19, SPEC 0202):
  /// two decimals, a decimal comma, a true minus sign, joined by " · ".
  ///
  /// Example: (-17.7923, -50.9187) -> "−17,79 · −50,92"
  static String coordinatesShort(double latitude, double longitude) {
    String part(double value) =>
        value.toStringAsFixed(2).replaceAll('-', '\u2212').replaceAll('.', ',');
    return '${part(latitude)} · ${part(longitude)}';
  }

  /// Formats a GPS accuracy radius in metres, rounded up so the shown radius
  /// never claims more precision than the device reported.
  ///
  /// Example: 4.2 -> "± 5 m"
  static String horizontalAccuracy(double metres) {
    return '± ${metres.ceil()} m';
  }

  /// An estimated distance in millimetres, as whole centimetres marked
  /// approximate (SPEC 0238).
  ///
  /// Example: 339 -> "≈ 34 cm"
  static String distanceCm(double millimetres) {
    return '≈ ${(millimetres / 10).round()} cm';
  }

  /// An illuminance, whole below 100 lx and to the nearest 10 from there,
  /// with a dot between thousands (SPEC 0238).
  ///
  /// Example: 1483 -> "1.480 lx"
  static String lux(double lux) {
    final rounded = lux < 100 ? lux.round() : (lux / 10).round() * 10;
    final grouped = rounded.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+$)'),
      (_) => '.',
    );
    return '$grouped lx';
  }
}
