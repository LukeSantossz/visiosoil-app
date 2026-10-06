import 'package:visiosoil_app/core/services/capture_guide_store.dart';

/// In-memory [CaptureGuideStore] for tests: seeds whether the guide was seen,
/// counts the marks, can fail a read or a write, and can hold a write open
/// until [writeGate] completes.
class FakeCaptureGuideStore implements CaptureGuideStore {
  FakeCaptureGuideStore({
    this.seen = false,
    this.readError,
    this.writeError,
    this.writeGate,
  });

  bool seen;
  int markCalls = 0;
  final Exception? readError;
  final Exception? writeError;
  final Future<void>? writeGate;

  @override
  Future<bool> hasSeenCaptureGuide() async {
    final error = readError;
    if (error != null) throw error;
    return seen;
  }

  @override
  Future<void> markCaptureGuideSeen() async {
    markCalls++;
    final gate = writeGate;
    if (gate != null) await gate;
    final error = writeError;
    if (error != null) throw error;
    seen = true;
  }
}
