import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One uncaught error as the report keeps it (SPEC 0110).
class ErrorReportEntry {
  const ErrorReportEntry({
    required this.time,
    required this.source,
    required this.type,
    this.library,
    required this.message,
    required this.stack,
  });

  /// When the error was recorded, in UTC.
  final DateTime time;

  /// `framework` for an error `FlutterError.onError` saw, `platform` for one
  /// `PlatformDispatcher.onError` saw.
  final String source;

  /// The error's runtime type.
  final String type;

  /// The library `FlutterErrorDetails` names, for a framework error.
  final String? library;

  /// The error's message, redacted and cut to [ErrorReportStore.messageLimit].
  final String message;

  /// The stack trace's first [ErrorReportStore.stackLineLimit] lines.
  final String stack;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'source': source,
        'type': type,
        'library': library,
        'message': message,
        'stack': stack,
      };

  factory ErrorReportEntry.fromJson(Map<String, dynamic> json) =>
      ErrorReportEntry(
        time: DateTime.parse(json['time'] as String).toUtc(),
        source: json['source'] as String,
        type: json['type'] as String,
        library: json['library'] as String?,
        message: json['message'] as String,
        stack: json['stack'] as String,
      );
}

/// Keeps the newest uncaught Dart errors in a file on the device, for the user
/// to share from Settings (SPEC 0110, #287). Nothing leaves the device unless
/// the user sends it.
///
/// A message is kept because it names the input that failed, and for the same
/// reason it can echo that input, so it is [redact]ed and cut before it is
/// written. An address is free text no pattern finds, and is the residual risk
/// the Developer accepted at the Spec Gate.
class ErrorReportStore {
  ErrorReportStore({
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  })  : _directory = directory ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now;

  /// How many entries the report keeps; recording one more drops the oldest.
  static const capacity = 50;

  /// How many characters of a redacted message are kept.
  static const messageLimit = 300;

  /// How many lines of a stack trace are kept.
  static const stackLineLimit = 40;

  static const _fileName = 'error_report.jsonl';

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  /// The queue every write joins, so two errors arriving together cannot
  /// interleave. It never completes with an error: [_enqueue] catches all.
  Future<void> _tail = Future.value();

  /// The last entry written, minus its time. A widget that fails on every
  /// rebuild reports the same error each frame, and an entry equal to this one
  /// is dropped without touching the file.
  String? _lastSignature;

  /// Records an error that reached `PlatformDispatcher.onError`, or any other
  /// error with its [source]. Never throws.
  Future<void> record({
    required String source,
    required Object error,
    StackTrace? stack,
    String? library,
  }) {
    final time = _clock().toUtc();
    return _enqueue(() => ErrorReportEntry(
          time: time,
          source: source,
          type: error.runtimeType.toString(),
          library: library,
          message: _cut(redact(error.toString())),
          stack: _firstLines('${stack ?? ''}'),
        ));
  }

  /// Records an error that reached `FlutterError.onError`. Never throws.
  Future<void> recordFlutterError(FlutterErrorDetails details) {
    final time = _clock().toUtc();
    return _enqueue(() => ErrorReportEntry(
          time: time,
          source: 'framework',
          type: details.exception.runtimeType.toString(),
          library: details.library,
          message: _cut(redact(details.exceptionAsString())),
          stack: _firstLines('${details.stack ?? ''}'),
        ));
  }

  /// Completes when every write queued so far has finished.
  @visibleForTesting
  Future<void> settled() => _tail;

  /// The kept entries, oldest first. A line that cannot be decoded, such as a
  /// write cut short, is skipped.
  Future<List<ErrorReportEntry>> entries() async {
    await _tail;
    final file = await _file();
    if (!await file.exists()) return const [];
    final entries = <ErrorReportEntry>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        entries.add(ErrorReportEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        ));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return entries;
  }

  Future<bool> get isEmpty async => (await entries()).isEmpty;

  /// Deletes the report. Unlike recording, a failure here reaches the caller,
  /// because the user asked for it and must not be told it is gone when it is
  /// not.
  ///
  /// The deletion joins the write queue, so an error recorded while it runs is
  /// written after it rather than racing it. The queue itself swallows the
  /// failure, so later writes still run.
  Future<void> clear() {
    final cleared = _tail.then((_) async {
      final file = await _file();
      if (await file.exists()) await file.delete();
      _lastSignature = null;
    });
    _tail = cleared.then((_) {}, onError: (Object _) {});
    return cleared;
  }

  /// The report as text to share: a header naming the build and the OS, then
  /// each entry, oldest first. It names no device identifier and no account.
  Future<String> render({
    required String appVersion,
    required String osVersion,
  }) async {
    final kept = await entries();
    final text = StringBuffer()
      ..writeln('VisioSoil $appVersion · $osVersion')
      ..writeln('${kept.length} erro(s), do mais antigo ao mais recente.');
    for (final entry in kept) {
      text
        ..writeln()
        ..writeln('[${entry.time.toIso8601String()}] '
            '${entry.source} · ${entry.type}');
      if (entry.library != null) text.writeln('library: ${entry.library}');
      text
        ..writeln(entry.message)
        ..writeln(entry.stack);
    }
    return text.toString();
  }

  /// Removes from [message] what could identify a place, a session or a person:
  /// decimals with three or more fractional digits (a coordinate in any form
  /// the app prints), OAuth tokens, JWTs, long unbroken runs that may be
  /// secrets or identifiers, and email addresses.
  @visibleForTesting
  static String redact(String message) => message
      .replaceAll(_email, '<email>')
      .replaceAll(_oauthToken, '<token>')
      .replaceAll(_jwt, '<token>')
      .replaceAll(_preciseDecimal, '<number>')
      .replaceAll(_longRun, '<token>');

  static final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
  static final _oauthToken = RegExp(r'ya29\.[\w-]+');
  static final _jwt = RegExp(r'eyJ[\w-]*\.[\w-]+\.[\w-]+');
  static final _preciseDecimal = RegExp(r'-?\d+\.\d{3,}');
  static final _longRun = RegExp(r'[A-Za-z0-9_\-+/=]{24,}');

  static String _cut(String message) => message.length <= messageLimit
      ? message
      : message.substring(0, messageLimit);

  static String _firstLines(String stack) {
    final lines = const LineSplitter().convert(stack);
    return (lines.length <= stackLineLimit
            ? lines
            : lines.sublist(0, stackLineLimit))
        .join('\n');
  }

  Future<File> _file() async => File('${(await _directory()).path}/$_fileName');

  Future<void> _enqueue(ErrorReportEntry Function() build) =>
      _tail = _tail.then((_) async {
        try {
          final entry = build();
          final signature = '${entry.source}\u0000${entry.type}\u0000'
              '${entry.library}\u0000${entry.message}\u0000${entry.stack}';
          if (signature == _lastSignature) return;
          final file = await _file();
          final lines = await file.exists()
              ? (await file.readAsLines()).where((l) => l.trim().isNotEmpty)
                  .toList()
              : <String>[];
          lines.add(jsonEncode(entry.toJson()));
          final kept = lines.length > capacity
              ? lines.sublist(lines.length - capacity)
              : lines;
          await file.writeAsString('${kept.join('\n')}\n', flush: true);
          _lastSignature = signature;
        } catch (e) {
          // This runs for an error handler, the outermost boundary there is,
          // so it catches everything: a throw here would recurse into the
          // handler or replace the error being reported. Only the failure's
          // type is logged, since its message could quote the report.
          developer.log(
            'could not record an uncaught error (${e.runtimeType})',
            name: 'ErrorReportStore',
          );
        }
      });
}

/// Sends every uncaught Dart error to [store] (SPEC 0110).
///
/// The framework handler it replaces still runs, so debug builds keep printing
/// and showing the red screen. The platform handler returns false, which leaves
/// the engine's default reporting in place; an uncaught Dart error does not end
/// the process either way.
void installErrorReporting(ErrorReportStore store) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(store.recordFlutterError(details));
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(store.record(source: 'platform', error: error, stack: stack));
    return false;
  };
}
