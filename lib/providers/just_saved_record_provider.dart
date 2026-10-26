import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The record a capture save just wrote, until details has played its
/// bookmark pop for it (redesign v11 §7, SPEC 0197).
class JustSavedRecordNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void mark(int recordId) => state = recordId;

  void clear() => state = null;
}

/// Read once by details, which clears it; null when no save is pending.
final justSavedRecordProvider =
    NotifierProvider<JustSavedRecordNotifier, int?>(JustSavedRecordNotifier.new);
