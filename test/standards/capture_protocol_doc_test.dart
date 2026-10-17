import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/widgets/classification_failure_chip.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// `docs/capture-protocol.md` tells a photographer two limits the code derives
/// from the released contract (SPEC 0164). A contract re-released with another
/// scale, patch size or floor would move them while the document kept the old
/// figures, and the next session of photographs would be taken to a protocol
/// the app no longer reads. These tests recompute both figures and read the
/// document for them.
void main() {
  late String protocol;
  late DescriptorContract contract;

  setUpAll(() {
    protocol = File('docs/capture-protocol.md').readAsStringSync();
    final parsed = parseDescriptorContract(
      File('assets/models/spec.json').readAsStringSync(),
    );
    expect(parsed.cause, isNull);
    contract = parsed.contract!;
  });

  test('the_protocol_states_the_least_sheet_span_the_contract_allows', () {
    // Coarser than the canonical scale is refused as too coarse, so the
    // sheet's long side must span at least this many photographed pixels.
    final leastSpanPx = (sheetHeightMm / contract.canonicalMmPerPx).ceil();
    expect(protocol, contains('$leastSpanPx px'));
  });

  test('the_protocol_states_the_least_soil_circle_nine_patches_need', () {
    final leastDiscMm =
        _leastAcceptedDiscPx(contract) * contract.canonicalMmPerPx;
    final leastCircleMm = (leastDiscMm + 2 * soilMarginMm).ceil();
    expect(protocol, contains('$leastCircleMm mm'));
  });

  test('the_protocol_names_every_refusal_a_retake_fixes', () {
    const contractCauses = {
      ClassificationFailureCause.contractMissing,
      ClassificationFailureCause.contractMalformed,
      ClassificationFailureCause.contractUnsupported,
    };
    final retakeCauses = ClassificationFailureCause.values.where(
      (cause) =>
          !contractCauses.contains(cause) &&
          !classificationFailureChip(cause).retryable,
    );
    expect(retakeCauses, isNotEmpty);
    for (final cause in retakeCauses) {
      expect(protocol, contains('`${cause.name}`'), reason: cause.name);
      expect(
        protocol,
        contains(classificationFailureChip(cause).label),
        reason: '${cause.name} chip label',
      );
    }
  });
}

/// The smallest disc diameter, in canonical pixels, that holds the contract's
/// floor of patches, to a hundredth of a pixel.
double _leastAcceptedDiscPx(DescriptorContract contract) {
  bool accepts(double diameterPx) =>
      patchGeometry(
        regionDiameterPx: diameterPx,
        patchPx: contract.patchPx,
        canonicalMmPerPx: contract.canonicalMmPerPx,
        minPatches: contract.minPatches,
        strideFraction: contract.patchStrideFraction,
      ).geometry !=
      null;

  var refused = 1.0;
  var accepted = contract.patchPx * 10.0;
  expect(accepts(accepted), isTrue, reason: 'search bound holds no grid');
  while (accepted - refused > 0.01) {
    final middle = (refused + accepted) / 2;
    if (accepts(middle)) {
      accepted = middle;
    } else {
      refused = middle;
    }
  }
  return accepted;
}
