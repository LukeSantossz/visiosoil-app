import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// `docs/capture-protocol.md` and its pt-BR version tell a photographer two
/// limits the code derives from the released contract (SPEC 0164). A contract
/// re-released with another scale, patch size or floor would move them while
/// the documents kept the old figures, and the next session of photographs
/// would be taken to a protocol the app no longer reads. These tests recompute
/// both figures and read each document for them.
void main() {
  const documents = [
    'docs/capture-protocol.md',
    'docs/capture-protocol.pt-BR.md',
  ];
  late DescriptorContract contract;

  setUpAll(() {
    final parsed = parseDescriptorContract(
      File('assets/models/spec.json').readAsStringSync(),
    );
    expect(parsed.cause, isNull);
    contract = parsed.contract!;
  });

  for (final path in documents) {
    group(path, () {
      test('the_protocol_states_the_least_sheet_span_the_contract_allows', () {
        final protocol = File(path).readAsStringSync();
        // Coarser than the canonical scale is refused as too coarse, so the
        // sheet's long side must span at least this many photographed pixels.
        final leastSpanPx = (sheetHeightMm / contract.canonicalMmPerPx).ceil();
        expect(protocol, contains('$leastSpanPx px'));
      });

      test('the_protocol_states_the_least_soil_circle_nine_patches_need', () {
        final protocol = File(path).readAsStringSync();
        final leastDiscMm =
            _leastAcceptedDiscPx(contract) * contract.canonicalMmPerPx;
        final leastCircleMm = (leastDiscMm + 2 * soilMarginMm).ceil();
        expect(protocol, contains('$leastCircleMm mm'));
      });

      test('the_protocol_names_every_refusal_a_retake_fixes', () {
        final protocol = File(path).readAsStringSync();
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
        final rows = protocol.split('\n').where((line) => line.startsWith('|'));
        for (final cause in retakeCauses) {
          // The cause and its chip's label share one table row, so a label
          // moved to another cause's row is caught.
          final row = rows.where((line) => line.contains('`${cause.name}`'));
          expect(row, hasLength(1), reason: cause.name);
          expect(
            row.single,
            contains(classificationFailureChip(cause).label),
            reason: '${cause.name} chip label',
          );
        }
      });
    });
  }

  // The pt-BR copy states the same steps and limits as the English source
  // (SPEC 0164, amended 2026-10-18): a step, a limit or a cause added to one
  // document and not the other fails here.
  test('the_translations_state_the_same_steps_and_limits', () {
    final source = _sections(File(documents[0]).readAsStringSync());
    final copy = _sections(File(documents[1]).readAsStringSync());
    expect(copy, hasLength(source.length), reason: 'section count');
    for (var i = 0; i < source.length; i++) {
      final where = 'section $i (${source[i].split('\n').first})';
      expect(_items(copy[i]), _items(source[i]), reason: '$where items');
      expect(_numbers(copy[i]), _numbers(source[i]), reason: '$where numbers');
      expect(_names(copy[i]), _names(source[i]), reason: '$where names');
    }
  });
}

/// [document] split at its `## ` headings, the text before the first one
/// included.
List<String> _sections(String document) => document
    .replaceAll('\r\n', '\n')
    .split(RegExp(r'^## ', multiLine: true));

/// [section]'s list items and table rows in order, each as its kind and its
/// indent on its own line, so a nested item or a row traded for an item is
/// told apart.
List<String> _items(String section) => [
      for (final match
          in RegExp(r'^([ \t]*)([-*+] |\d+\. |\|)', multiLine: true)
              .allMatches(section))
        '${match.group(2)!.startsWith('|') ? 'row' : 'item'}'
            '@${match.group(1)!.length}',
    ];

/// Every number in [section], a decimal comma read as a point, link targets
/// left out, sorted.
List<String> _numbers(String section) => [
      for (final match in RegExp(r'\d+(?:[.,]\d+)?')
          .allMatches(section.replaceAll(RegExp(r'\]\([^)]*\)'), ']')))
        match.group(0)!.replaceAll(',', '.'),
    ]..sort();

/// The backticked names in [section], less the two documents' own file
/// names: each points to the other, so those differ by design.
Set<String> _names(String section) => {
      for (final match in RegExp('`([^`]+)`').allMatches(section))
        match.group(1)!,
    }..removeAll({'capture-protocol.md', 'capture-protocol.pt-BR.md'});

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
