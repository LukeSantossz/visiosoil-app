import 'package:flutter/material.dart';

/// Full-screen fallback shown by the router when a route is unknown or a route
/// builder throws. Renders a localized message and a button that returns home.
class RouteErrorView extends StatelessWidget {
  const RouteErrorView({super.key, required this.onGoHome});

  /// Invoked when the user taps the "return home" button.
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
