// Guards the durable-numbering rule from .standards/docs/standards/spec_method.md:
// a spec or ADR number is never reused, a superseded record is marked Retired in
// place rather than deleted, and the numbers run from 0001 with no gap.
//
// The rule protects the number a reference resolves to, not a filename, so every
// check below works over sets of numbers. Renaming 0009-old-slug.md to
// 0009-new-slug.md keeps the number and is therefore not a deletion.
//
// Contiguity is enforced on `main` only. On a feature branch a missing number is
// normally one legitimately reserved by a concurrent pull request, which is what
// happened with specs 0011 (#138) and 0012 (#139).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _specsDir = 'docs/specs';
const _adrDir = 'docs/adr';

/// Numbers deliberately retired, mapped to the reason. A retirement must leave a
/// trace, so an entry without a reason is itself a failure.
const retiredSpecNumbers = <String, String>{};
const retiredAdrNumbers = <String, String>{};

final _numberedRecord = RegExp(r'(\d{4})-[a-z0-9-]+\.md$');

// --- Pure rules, exercised directly below so each one is tested rather than
// merely observed against whatever the repository happens to contain today. ---

/// The record numbers appearing in [paths] under [dirPrefix].
Set<String> numbersUnder(Iterable<String> paths, String dirPrefix) {
  final numbers = <String>{};
  for (final path in paths) {
    final normalized = path.replaceAll(r'\', '/');
    if (!normalized.startsWith('$dirPrefix/')) continue;
    final match = _numberedRecord.firstMatch(normalized);
    if (match != null) numbers.add(match.group(1)!);
  }
  return numbers;
}

/// Numbers carried by more than one record file at once.
List<String> duplicateNumbers(Iterable<String> filenames) {
  final counts = <String, int>{};
  for (final name in filenames) {
    final match = _numberedRecord.firstMatch(name.replaceAll(r'\', '/'));
    if (match != null) {
      counts.update(match.group(1)!, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return counts.entries.where((e) => e.value > 1).map((e) => e.key).toList()
    ..sort();
}

/// Numbers missing from a run that should start at 0001 and have no hole.
List<String> gapsIn(Set<String> numbers) {
  if (numbers.isEmpty) return const [];
  final present = numbers.map(int.parse).toSet();
  final highest = present.reduce((a, b) => a > b ? a : b);
  return [
    for (var n = 1; n <= highest; n++)
      if (!present.contains(n)) n.toString().padLeft(4, '0'),
  ];
}

/// Numbers that history shows were committed but are absent today and not
/// allowlisted as retired.
List<String> vanishedNumbers({
  required Set<String> everCommitted,
  required Set<String> presentNow,
  required Map<String, String> retired,
}) =>
    (everCommitted.difference(presentNow)..removeAll(retired.keys)).toList()
      ..sort();

/// Allowlist entries that fail to state why the number was retired.
List<String> allowlistEntriesWithoutReason(Map<String, String> retired) =>
    retired.entries.where((e) => e.value.trim().isEmpty).map((e) => e.key).toList()
      ..sort();

/// `false` to run the contiguity checks, or the reason they are skipped.
///
/// A `pull_request` CI run checks out a detached merge commit, so the branch
/// reads as `HEAD` and contiguity is skipped there by the same rule that skips
/// it on a local feature branch.
Object contiguitySkipReason(String branch) => branch == 'main'
    ? false
    : 'contiguity is enforced on main only; on "$branch" a missing number is '
        'normally one reserved by a concurrent pull request';

// --- Repository state ---

ProcessResult _git(List<String> args) => Process.runSync('git', args);

String _currentBranch() =>
    (_git(['rev-parse', '--abbrev-ref', 'HEAD']).stdout as String).trim();

List<String> _presentRecords(String dir) => Directory(dir)
    .listSync()
    .whereType<File>()
    .map((f) => '$dir/${f.uri.pathSegments.last}')
    .toList();

/// Every record path this branch's history has ever contained.
///
/// Scoped to HEAD rather than `--all`: a record on an unrelated branch was never
/// committed *here*, and counting it would report a deletion that never happened.
List<String> _recordsEverCommitted() {
  // Ask git directly whether history is truncated. Inferring it from an empty
  // result is not enough: a depth-1 clone whose tip commit happens to touch a
  // spec still yields paths, so the guard would pass while every deletion before
  // the shallow boundary stayed invisible.
  final shallow = _git(['rev-parse', '--is-shallow-repository']);
  expect(
    (shallow.stdout as String).trim(),
    'false',
    reason: 'the repository is a shallow clone, so deletions before the '
        'boundary cannot be seen; CI must check out with fetch-depth: 0',
  );

  final result = _git([
    'log',
    '--pretty=format:',
    '--name-only',
    'HEAD',
    '--',
    _specsDir,
    _adrDir,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'git log failed, so the deletion guard cannot run: ${result.stderr}',
  );
  final paths = (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  // Secondary sanity check, now that shallowness is ruled out above: a full
  // history that still shows no record at all means the query itself is wrong.
  expect(
    paths,
    isNotEmpty,
    reason: 'git history shows no spec or ADR files ever committed, which '
        'cannot be true of a full clone of this repository',
  );
  return paths;
}

void main() {
  final branch = _currentBranch();
  final skipContiguity = contiguitySkipReason(branch);

  group('durable numbering rules', () {
    test('numbers_are_read_from_the_record_number_not_the_slug', () {
      final numbers = numbersUnder([
        'docs/specs/0009-old-slug.md',
        'docs/specs/0010-another.md',
        'docs/adr/0001-elsewhere.md',
        'docs/specs/README.md',
      ], _specsDir);

      expect(numbers, {'0009', '0010'});
    });

    test('a_renamed_record_keeping_its_number_does_not_read_as_a_deletion', () {
      // History holds both filenames; the number never left.
      final everCommitted = numbersUnder([
        'docs/specs/0009-old-slug.md',
        'docs/specs/0009-new-slug.md',
      ], _specsDir);
      final presentNow = numbersUnder(
        ['docs/specs/0009-new-slug.md'],
        _specsDir,
      );

      expect(
        vanishedNumbers(
          everCommitted: everCommitted,
          presentNow: presentNow,
          retired: const {},
        ),
        isEmpty,
      );
    });

    test('a_removed_number_reads_as_a_deletion_unless_allowlisted', () {
      const ever = {'0001', '0002'};
      const now = {'0001'};

      expect(
        vanishedNumbers(everCommitted: ever, presentNow: now, retired: const {}),
        ['0002'],
      );
      expect(
        vanishedNumbers(
          everCommitted: ever,
          presentNow: now,
          retired: const {'0002': 'withdrawn before implementation'},
        ),
        isEmpty,
      );
    });

    test('an_allowlisted_retirement_requires_a_non_empty_reason', () {
      expect(
        allowlistEntriesWithoutReason(const {'0002': 'superseded by 0007'}),
        isEmpty,
      );
      expect(
        allowlistEntriesWithoutReason(const {'0002': '   ', '0003': ''}),
        ['0002', '0003'],
      );
    });

    test('duplicate_numbers_are_reported', () {
      expect(
        duplicateNumbers([
          'docs/specs/0001-one.md',
          'docs/specs/0001-one-again.md',
          'docs/specs/0002-two.md',
        ]),
        ['0001'],
      );
      expect(duplicateNumbers(['docs/specs/0001-one.md']), isEmpty);
    });

    test('gaps_are_reported_against_a_run_starting_at_0001', () {
      expect(gapsIn({'0001', '0002', '0004'}), ['0003']);
      expect(gapsIn({'0002'}), ['0001']);
      expect(gapsIn({'0001', '0002'}), isEmpty);
      expect(gapsIn(<String>{}), isEmpty);
    });

    test('contiguity_is_skipped_with_a_stated_reason_when_not_on_main', () {
      expect(contiguitySkipReason('main'), isFalse);

      final reason = contiguitySkipReason('test/140-guard-durable-numbering');
      expect(reason, isA<String>());
      expect(reason as String, contains('concurrent pull request'));
    });
  });

  group('this repository', () {
    test('spec_numbers_have_no_duplicates', () {
      expect(duplicateNumbers(_presentRecords(_specsDir)), isEmpty);
    });

    test('adr_numbers_have_no_duplicates', () {
      expect(duplicateNumbers(_presentRecords(_adrDir)), isEmpty);
    });

    test('no_number_ever_committed_is_absent_unless_allowlisted', () {
      final ever = _recordsEverCommitted();

      expect(
        vanishedNumbers(
          everCommitted: numbersUnder(ever, _specsDir),
          presentNow: numbersUnder(_presentRecords(_specsDir), _specsDir),
          retired: retiredSpecNumbers,
        ),
        isEmpty,
        reason: 'a spec number was deleted rather than retired in place',
      );
      expect(
        vanishedNumbers(
          everCommitted: numbersUnder(ever, _adrDir),
          presentNow: numbersUnder(_presentRecords(_adrDir), _adrDir),
          retired: retiredAdrNumbers,
        ),
        isEmpty,
        reason: 'an ADR number was deleted rather than retired in place',
      );
    });

    test('the_retirement_allowlists_state_their_reasons', () {
      expect(allowlistEntriesWithoutReason(retiredSpecNumbers), isEmpty);
      expect(allowlistEntriesWithoutReason(retiredAdrNumbers), isEmpty);
    });

    test(
      'spec_numbers_are_contiguous_from_0001_on_main',
      () {
        expect(
          gapsIn(numbersUnder(_presentRecords(_specsDir), _specsDir)),
          isEmpty,
        );
      },
      skip: skipContiguity,
    );

    test(
      'adr_numbers_are_contiguous_from_0001_on_main',
      () {
        expect(gapsIn(numbersUnder(_presentRecords(_adrDir), _adrDir)), isEmpty);
      },
      skip: skipContiguity,
    );
  });
}
