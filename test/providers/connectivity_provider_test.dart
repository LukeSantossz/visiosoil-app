// Tests for the connectivity layer: the domain-enum mapping and the Riverpod
// stream that surfaces online/offline transitions.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';

class _FakeConnectivityService implements ConnectivityService {
  _FakeConnectivityService(this._controller);

  final StreamController<ConnectivityStatus> _controller;

  @override
  Stream<ConnectivityStatus> watch() => _controller.stream;

  @override
  Future<ConnectivityStatus> current() async => ConnectivityStatus.offline;
}

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this._results);

  final List<ConnectivityResult> _results;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value(_results);
}

void main() {
  test('connectivity_provider_emits_on_status_change', () async {
    final controller = StreamController<ConnectivityStatus>();
    final container = ProviderContainer(
      overrides: [
        connectivityServiceProvider
            .overrideWithValue(_FakeConnectivityService(controller)),
      ],
    );
    addTearDown(container.dispose);

    final emissions = <ConnectivityStatus>[];
    final sub = container.listen<AsyncValue<ConnectivityStatus>>(
      connectivityStatusProvider,
      (_, next) {
        if (next is AsyncData<ConnectivityStatus>) emissions.add(next.value);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    controller.add(ConnectivityStatus.online);
    await Future<void>.delayed(Duration.zero);
    controller.add(ConnectivityStatus.offline);
    await Future<void>.delayed(Duration.zero);

    expect(emissions, [ConnectivityStatus.online, ConnectivityStatus.offline]);
    await controller.close();
  });

  test('maps_active_interface_to_online', () async {
    final service = ConnectivityPlusService(
      _FakeConnectivity([ConnectivityResult.wifi]),
    );
    expect(await service.current(), ConnectivityStatus.online);
  });

  test('maps_no_interface_to_offline', () async {
    final service = ConnectivityPlusService(
      _FakeConnectivity([ConnectivityResult.none]),
    );
    expect(await service.current(), ConnectivityStatus.offline);
  });
}
