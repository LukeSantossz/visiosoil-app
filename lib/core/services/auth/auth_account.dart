/// The signed-in Google account, as the app consumes it (no plugin types leak).
class AuthAccount {
  const AuthAccount({required this.email, required this.displayName});

  final String email;
  final String? displayName;
}
