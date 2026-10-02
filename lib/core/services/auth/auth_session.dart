/// Persisted authentication session: the signed-in account.
///
/// Sign-in asks for identity only, so there is no token to keep (SPEC 0106).
/// A feature that needs a token requests and holds its own.
class AuthSession {
  const AuthSession({
    required this.email,
    required this.displayName,
  });

  final String email;
  final String? displayName;

  Map<String, dynamic> toJson() => {
        'email': email,
        'displayName': displayName,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        email: json['email'] as String,
        displayName: json['displayName'] as String?,
      );
}
