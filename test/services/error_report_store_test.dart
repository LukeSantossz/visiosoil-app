// The local report of uncaught errors (SPEC 0110, #287): what an entry holds,
// what redaction removes from its message, the cap, and that the handlers never
// throw. The store writes to a temporary directory, so no platform channel is
// touched.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';

void main() {
  late Directory dir;
  late ErrorReportStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('error_report_test');
    store = ErrorReportStore(directory: () async => dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Installs the hooks for [body], restoring both handlers afterwards: the
  /// test harness fails a test that leaves `FlutterError.onError` changed.
  Future<void> withHooks(
    ErrorReportStore store,
    Future<void> Function() body, {
    FlutterExceptionHandler? previous,
  }) async {
    final savedFramework = FlutterError.onError;
    final savedPlatform = PlatformDispatcher.instance.onError;
    FlutterError.onError = previous ?? (_) {};
    try {
      installErrorReporting(store);
      await body();
    } finally {
      FlutterError.onError = savedFramework;
      PlatformDispatcher.instance.onError = savedPlatform;
    }
  }

  test('an_uncaught_error_is_recorded_with_its_type_and_stack', () async {
    await withHooks(store, () async {
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('framework failure'),
        stack: StackTrace.current,
        library: 'widgets library',
      ));
      final handled = PlatformDispatcher.instance.onError!(
        ArgumentError('platform failure'),
        StackTrace.current,
      );
      // False leaves the engine's default reporting in place.
      expect(handled, isFalse);
    });
    await store.settled();

    final entries = await store.entries();
    expect(entries, hasLength(2));
    expect(entries[0].source, 'framework');
    expect(entries[0].type, 'StateError');
    expect(entries[0].library, 'widgets library');
    expect(entries[0].stack, isNotEmpty);
    expect(entries[1].source, 'platform');
    expect(entries[1].type, 'ArgumentError');
    expect(entries[1].library, isNull);
    expect(entries[1].stack, isNotEmpty);
  });

  test('the_report_redacts_coordinates_tokens_and_emails', () async {
    await store.record(
      source: 'platform',
      error: Exception(
        'while saving at -22.906847, -47.061630 '
        '(raw -22.90684712345678, -47.06163098765432) '
        'with ya29.a0AfH6SMBxyz-_123 and '
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.SflKxwRJSMeKKF2QT4fwpM '
        'for agro@example.com',
      ),
      stack: StackTrace.current,
    );

    final message = (await store.entries()).single.message;
    for (final leaked in [
      '22.906847',
      '47.061630',
      '22.90684712345678',
      'ya29',
      'eyJ',
      'agro@example.com',
    ]) {
      expect(message, isNot(contains(leaked)), reason: '$leaked survived');
    }
    expect(message, contains('<number>'));
    expect(message, contains('<token>'));
    expect(message, contains('<email>'));
    // What is not data is kept, so the message still says what failed.
    expect(message, contains('while saving at'));
  });

  test('a_long_message_is_cut_to_300_characters', () async {
    // Spaces break every run, so redaction leaves this message whole.
    final long = 'ab ' * 334;
    await store.record(
      source: 'platform',
      error: Exception(long),
      stack: StackTrace.current,
    );

    final message = (await store.entries()).single.message;
    expect(message, hasLength(300));
    expect(message, 'Exception: $long'.substring(0, 300));
  });

  test('the_report_keeps_the_newest_fifty_entries', () async {
    for (var i = 0; i <= 50; i++) {
      await store.record(
        source: 'platform',
        error: Exception('error $i'),
        stack: StackTrace.current,
      );
    }

    final entries = await store.entries();
    expect(entries, hasLength(50));
    expect(entries.first.message, 'Exception: error 1');
    expect(entries.last.message, 'Exception: error 50');
  });

  test('a_repeating_error_is_kept_once', () async {
    // A widget that fails on every rebuild reports the same error each frame;
    // the report keeps it once rather than rewriting the file each time.
    final stack = StackTrace.current;
    for (var i = 0; i < 5; i++) {
      await store.record(source: 'platform', error: StateError('loop'), stack: stack);
    }
    await store.record(source: 'platform', error: StateError('other'), stack: stack);
    await store.record(source: 'platform', error: StateError('loop'), stack: stack);

    final messages = [for (final e in await store.entries()) e.message];
    expect(messages, [
      'Bad state: loop',
      'Bad state: other',
      'Bad state: loop',
    ]);
  });

  test('a_failed_write_never_throws_from_the_handler', () async {
    final broken = ErrorReportStore(
      directory: () async => throw const FileSystemException('denied'),
    );

    await withHooks(broken, () async {
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('framework failure'),
        stack: StackTrace.current,
      ));
      expect(
        PlatformDispatcher.instance.onError!(
          ArgumentError('platform failure'),
          StackTrace.current,
        ),
        isFalse,
      );
    });

    // The queued writes failed, and nothing escaped them.
    await broken.settled();
  });

  test('the_previous_framework_handler_still_runs', () async {
    final seen = <FlutterErrorDetails>[];
    final details = FlutterErrorDetails(
      exception: StateError('framework failure'),
      stack: StackTrace.current,
    );

    await withHooks(
      store,
      () async => FlutterError.onError!(details),
      previous: seen.add,
    );

    expect(seen, [same(details)]);
  });

  test('clearing_empties_the_report', () async {
    await store.record(
      source: 'platform',
      error: Exception('error'),
      stack: StackTrace.current,
    );
    expect(await store.isEmpty, isFalse);

    await store.clear();

    expect(await store.isEmpty, isTrue);
    expect(await store.entries(), isEmpty);
  });

  test('an_error_recorded_while_clearing_is_kept', () async {
    // R3 on #324: the deletion joins the write queue, so an error that arrives
    // while the report is being cleared lands after it and survives.
    await store.record(
      source: 'platform',
      error: StateError('before'),
      stack: StackTrace.current,
    );

    final clearing = store.clear();
    final recording = store.record(
      source: 'platform',
      error: StateError('after'),
      stack: StackTrace.current,
    );
    await Future.wait([clearing, recording]);

    expect(
      (await store.entries()).map((e) => e.message),
      ['Bad state: after'],
    );
  });

  test('a_failed_clear_reaches_the_caller_and_the_queue_survives', () async {
    final failing = ErrorReportStore(
      directory: () async => throw const FileSystemException('unreadable'),
    );
    await expectLater(failing.clear(), throwsA(isA<FileSystemException>()));
    // A later write still runs; it fails quietly, as recording must.
    await failing.record(source: 'platform', error: StateError('x'));
    await failing.settled();
  });

  test('the_rendered_report_names_the_build_and_no_identifier', () async {
    await store.record(
      source: 'platform',
      error: Exception('error'),
      stack: StackTrace.current,
    );

    final text = await store.render(appVersion: '1.0.0+7', osVersion: 'Android 15');

    expect(text, startsWith('VisioSoil 1.0.0+7'));
    expect(text, contains('Android 15'));
    expect(text, contains('Exception: error'));
  });
}
