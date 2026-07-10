/// Formatting utilities for the app.
///
/// Centralizes formatting functions to avoid duplication (DRY).
class Formatters {
  Formatters._();

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
}
