import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';

/// Provides the [ConnectivityService] singleton. Overridden in tests with a
/// fake source.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityPlusService();
});

/// Reactive online/offline status, surfaced for the sync engine and the UI.
///
/// Backed by [ConnectivityService.watch], so it reacts to the network coming
/// and going rather than sampling once.
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  return ref.watch(connectivityServiceProvider).watch();
});
