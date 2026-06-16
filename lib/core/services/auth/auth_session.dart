/// Persisted authentication session: the signed-in account plus the current
/// OAuth access token and its expiry.
///
/// The long-lived refresh token is owned by the platform/plugin, not stored
/// here; only the short-lived access token is persisted and refreshed via
/// silent re-authentication.
class AuthSession {
  const AuthSession({
    required this.email,
    required this.displayName,
    required this.accessToken,
    required this.expiresAt,
  });

  final String email;
  final String? displayName;
  final String accessToken;

  /// Access-token expiry, in UTC.
  final DateTime expiresAt;

  /// Whether the access token is expired at [now].
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  Map<String, dynamic> toJson() => {
        'email': email,
        'displayName': displayName,
        'accessToken': accessToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        email: json['email'] as String,
        displayName: json['displayName'] as String?,
        accessToken: json['accessToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      );
}
