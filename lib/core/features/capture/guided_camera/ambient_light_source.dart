import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the guided camera reads the illuminance on the phone's face.
abstract interface class AmbientLightSource {
  /// The ambient light sensor's readings, in lux.
  Stream<double> get lux;
}

/// [AmbientLightSource] over `MainActivity`'s channel (SPEC 0238). Empty off
/// Android; a sensor error or a missing plugin ends in silence, not an error.
class PlatformAmbientLightSource implements AmbientLightSource {
  const PlatformAmbientLightSource();

  static const _channel = EventChannel('com.visiosoil.app/ambient_light');

  @override
  Stream<double> get lux {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    return _channel.receiveBroadcastStream().transform(
      StreamTransformer.fromHandlers(
        handleData: (event, sink) {
          if (event is num) sink.add(event.toDouble());
        },
        handleError: (error, stack, sink) {
          developer.log(
            'Ambient light unavailable: $error',
            name: 'PlatformAmbientLightSource',
          );
        },
      ),
    );
  }
}
