// Acceptance criterion for the committed release (SPEC 0082).
//
// `assets/models/spec.json` is the first release of the descriptor contract,
// written by `ml/src/release.py` and promoted by `ml/scripts/deploy_to_app.sh`.
// Nothing regenerates it in a test; this asserts that the reader the wiring
// will use accepts the file the app now ships.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';

const _releasePath = 'assets/models/spec.json';

void main() {
  test('the_committed_release_parses', () {
    final file = File(_releasePath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_releasePath is missing. Release it with '
          '`cd ml && python -m src.release --version v1 --model-version <v>` '
          'and `bash ml/scripts/deploy_to_app.sh v1`.',
    );
    final parsed = parseDescriptorContract(file.readAsStringSync());
    expect(parsed.cause, isNull);
    expect(parsed.contract!.datasetVersion, 'v1');
  });
}
