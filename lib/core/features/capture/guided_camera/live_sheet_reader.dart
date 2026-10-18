import 'dart:async';
import 'dart:isolate';

import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// One reading, tagged with the generation of the request it answers, so a
/// reply that arrives after a stop is recognised as stale (SPEC 0166).
typedef LiveReply = ({int generation, LiveReading reading});

/// Reads preview frames off the UI isolate.
abstract interface class LiveSheetReader {
  /// Asks for [frame] to be read. The reply carries [generation].
  void read(RgbFrame frame, int generation);

  /// The replies, in order. An error is the reader failing: the isolate threw
  /// or exited.
  Stream<LiveReply> get replies;

  /// Stops the reader. The replies end.
  void kill();
}

typedef LiveSheetReaderFactory = Future<LiveSheetReader> Function(
  LiveContract contract,
);

/// [LiveSheetReader] on one long-lived isolate, spawned once per stream,
/// because spawning one per frame costs more than reading it.
class IsolateLiveSheetReader implements LiveSheetReader {
  IsolateLiveSheetReader._(this._isolate, this._toWorker, this._ports);

  final Isolate _isolate;
  final SendPort _toWorker;
  final List<ReceivePort> _ports;
  final _replies = StreamController<LiveReply>();
  bool _killed = false;

  static Future<IsolateLiveSheetReader> spawn(LiveContract contract) async {
    final fromWorker = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final isolate = await Isolate.spawn(
      _readerMain,
      (fromWorker.sendPort, contract),
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
    );
    final messages = fromWorker.asBroadcastStream();
    final toWorker = await messages.first as SendPort;
    final reader = IsolateLiveSheetReader._(
      isolate,
      toWorker,
      [fromWorker, errors, exits],
    );
    messages.listen((message) {
      if (!reader._killed) reader._replies.add(message as LiveReply);
    });
    errors.listen((message) {
      if (reader._killed) return;
      final pair = message as List<Object?>;
      reader._replies.addError(
        RemoteError('${pair[0]}', '${pair[1]}'),
        StackTrace.fromString('${pair[1]}'),
      );
    });
    exits.listen((_) {
      if (reader._killed) return;
      reader._replies.addError(StateError('the live sheet reader exited'));
    });
    return reader;
  }

  @override
  Stream<LiveReply> get replies => _replies.stream;

  @override
  void read(RgbFrame frame, int generation) {
    if (_killed) return;
    _toWorker.send((
      generation,
      frame.width,
      frame.height,
      TransferableTypedData.fromList([frame.rgb]),
    ));
  }

  @override
  void kill() {
    if (_killed) return;
    _killed = true;
    _isolate.kill(priority: Isolate.immediate);
    for (final port in _ports) {
      port.close();
    }
    unawaited(_replies.close());
  }
}

/// The reader's isolate: answers each frame with its reading.
void _readerMain((SendPort, LiveContract) setup) {
  final (toMain, contract) = setup;
  final requests = ReceivePort();
  toMain.send(requests.sendPort);
  requests.listen((message) {
    final (generation, width, height, data) =
        message as (int, int, int, TransferableTypedData);
    final rgb = data.materialize().asUint8List();
    final reading = readSheet(RgbFrame(width, height, rgb), contract);
    toMain.send((generation: generation, reading: reading));
  });
}
