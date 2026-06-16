import 'package:connectivity_plus/connectivity_plus.dart';

/// Online/offline state of the device, as the rest of the app consumes it.
enum ConnectivityStatus { online, offline }

/// Observable connectivity, abstracted from `connectivity_plus` so the sync
/// layer and UI depend on a domain enum and the source can be faked in tests.
abstract class ConnectivityService {
  /// Emits a new status every time connectivity changes.
  Stream<ConnectivityStatus> watch();

  /// One-shot read of the current status.
  Future<ConnectivityStatus> current();
}

/// [ConnectivityService] backed by the `connectivity_plus` plugin.
///
/// Treats any active interface (wifi, mobile, ethernet, vpn, ...) as
/// [ConnectivityStatus.online]; only an empty result or
/// [ConnectivityResult.none] is [ConnectivityStatus.offline]. Interface
/// presence is not a reachability guarantee — true reachability checks belong
/// to a concrete backend and are out of scope here.
class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<ConnectivityStatus> watch() =>
      _connectivity.onConnectivityChanged.map(_mapResults);

  @override
  Future<ConnectivityStatus> current() async =>
      _mapResults(await _connectivity.checkConnectivity());

  ConnectivityStatus _mapResults(List<ConnectivityResult> results) {
    final hasActiveInterface =
        results.any((result) => result != ConnectivityResult.none);
    return hasActiveInterface
        ? ConnectivityStatus.online
        : ConnectivityStatus.offline;
  }
}
