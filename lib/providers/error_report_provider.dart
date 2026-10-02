import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';

/// The report of uncaught errors (SPEC 0110). `main` overrides it with the
/// store its error hooks write to, so Settings reads the same file.
final errorReportStoreProvider = Provider<ErrorReportStore>(
  (ref) => ErrorReportStore(),
);

/// Whether the report holds an entry, for Settings' share row. Re-read each
/// time Settings is built anew, and invalidated when the report is cleared.
/// Not retried: a report that cannot be read has nothing to send.
final errorReportHasEntriesProvider = FutureProvider.autoDispose<bool>(
  (ref) async => !await ref.watch(errorReportStoreProvider).isEmpty,
  retry: (_, _) => null,
);
