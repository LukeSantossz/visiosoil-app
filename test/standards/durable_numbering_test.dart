// Guards the durable-numbering rule from .standards/docs/standards/spec_method.md:
// a spec or ADR number is never reused, a superseded record is marked Retired in
// place rather than deleted, and the numbers run from 0001 with no gap.
//
// The rule is about ordering, not membership. Comparing the set of numbers ever
// committed against the set present today cannot tell a rename from a deletion
// followed by reassignment: in both, the number is there before and after. So the
// deletion and reuse checks replay each number's history in commit order.
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

/// Numbers whose slug changed in a commit that also rewrote the record enough for
/// git's similarity detection to record a delete plus an add rather than a
/// rename. Each needs a stated reason, same as a retirement.
const renamedWithRewriteSpecNumbers = <String, String>{};
const renamedWithRewriteAdrNumbers = <String, String>{};

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

/// Allowlist entries that fail to state why the number was retired or renamed.
List<String> allowlistEntriesWithoutReason(Map<String, String> allowlist) =>
    allowlist.entries
        .where((e) => e.value.trim().isEmpty)
        .map((e) => e.key)
        .toList()
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

/// One change to one record, in commit order.
class RecordEvent {
  const RecordEvent.added(this.number, this.slug)
      : status = 'A',
        newSlug = null;
  const RecordEvent.deleted(this.number, this.slug)
      : status = 'D',
        newSlug = null;
  const RecordEvent.renamed(this.number, this.slug, this.newSlug) : status = 'R';

  final String status;
  final String number;
  final String slug;
  final String? newSlug;
}

/// What replaying a number's history revealed.
class HistoryVerdict {
  const HistoryVerdict({required this.vanished, required this.reused});

  /// Numbers deleted and never restored.
  final List<String> vanished;

  /// Numbers emptied and then handed to a different record.
  final List<String> reused;
}

/// Replays [events] to separate the shapes a number's history can take:
/// continuous, renamed, deleted, restored, or reassigned.
///
/// Reuse is decided by counting how many distinct *records* ever held a number,
/// not by watching for an add into an emptied number. The latter is
/// order-dependent and misses a reassignment staged as add-then-delete —
/// `A(0009-old)`, `A(0009-new)`, `D(0009-old)` — which git emits whenever the
/// new slug sorts before the old one in a single commit. Two slugs belong to the
/// same record only when a rename links them, so a number held by more than one
/// record identity was reassigned, however the commits were ordered.
HistoryVerdict replayRecordHistory(List<RecordEvent> events) {
  final live = <String, Set<String>>{};
  // Per number: slug -> the record identity that slug belongs to.
  final identityOf = <String, Map<String, String>>{};

  for (final event in events) {
    final slugs = live.putIfAbsent(event.number, () => <String>{});
    final identities = identityOf.putIfAbsent(event.number, () => {});
    switch (event.status) {
      case 'A':
        identities.putIfAbsent(event.slug, () => event.slug);
        slugs.add(event.slug);
      case 'D':
        identities.putIfAbsent(event.slug, () => event.slug);
        slugs.remove(event.slug);
      case 'R':
        // A rename carries the record's identity to the new slug, so the pair
        // counts once.
        final carried = identities[event.slug] ?? event.slug;
        identities[event.slug] = carried;
        identities[event.newSlug!] = carried;
        slugs.remove(event.slug);
        slugs.add(event.newSlug!);
    }
  }

  final vanished = <String>[];
  final reused = <String>[];
  live.forEach((number, slugs) {
    if (slugs.isEmpty) vanished.add(number);
    final distinctRecords = identityOf[number]!.values.toSet();
    if (distinctRecords.length > 1) reused.add(number);
  });
  return HistoryVerdict(
    vanished: vanished..sort(),
    reused: reused..sort(),
  );
}

String _slug(String path) => path.replaceAll(r'\', '/').split('/').last;

String? _numberOf(String path) =>
    _numberedRecord.firstMatch(path.replaceAll(r'\', '/'))?.group(1);

bool _inDir(String path, String dirPrefix) =>
    path.replaceAll(r'\', '/').startsWith('$dirPrefix/');

/// Parses `git log --name-status --find-renames` output into ordered events for
/// records under [dirPrefix].
List<RecordEvent> parseHistory(String gitOutput, String dirPrefix) {
  final events = <RecordEvent>[];
  for (final line in gitOutput.split('\n')) {
    final parts = line.trim().split('\t');
    if (parts.length < 2) continue;
    final status = parts[0];

    if (status.startsWith('R') && parts.length >= 3) {
      final from = parts[1], to = parts[2];
      if (!_inDir(to, dirPrefix)) continue;
      final number = _numberOf(to);
      if (number == null) continue;
      // A rename that also changes the number vacates the old one and takes the
      // new one; only a same-number rename is continuity.
      if (_numberOf(from) == number) {
        events.add(RecordEvent.renamed(number, _slug(from), _slug(to)));
      } else {
        if (_numberOf(from) != null && _inDir(from, dirPrefix)) {
          events.add(RecordEvent.deleted(_numberOf(from)!, _slug(from)));
        }
        events.add(RecordEvent.added(number, _slug(to)));
      }
    } else if (status == 'A' || status == 'D') {
      final path = parts[1];
      if (!_inDir(path, dirPrefix)) continue;
      final number = _numberOf(path);
      if (number == null) continue;
      events.add(status == 'A'
          ? RecordEvent.added(number, _slug(path))
          : RecordEvent.deleted(number, _slug(path)));
    }
  }
  return events;
}

// --- Repository state ---

ProcessResult _git(List<String> args) => Process.runSync('git', args);

String _currentBranch() =>
    (_git(['rev-parse', '--abbrev-ref', 'HEAD']).stdout as String).trim();

List<String> _presentRecords(String dir) => Directory(dir)
    .listSync()
    .whereType<File>()
    .map((f) => '$dir/${f.uri.pathSegments.last}')
    .toList();

/// Every record change this branch's history contains, oldest first.
///
/// Scoped to HEAD rather than `--all`: a record on an unrelated branch was never
/// committed *here*, and counting it would report a deletion that never happened.
String _historyOutput() {
  // Ask git directly whether history is truncated. Inferring it from an empty
  // result is not enough: a depth-1 clone's grafted root commit lists every
  // tracked file as an addition, so the query returns plenty and the guard would
  // pass while every deletion before the boundary stayed invisible.
  final shallow = _git(['rev-parse', '--is-shallow-repository']);
  expect(
    (shallow.stdout as String).trim(),
    'false',
    reason: 'the repository is a shallow clone, so deletions before the '
        'boundary cannot be seen; CI must check out with fetch-depth: 0',
  );

  final result = _git([
    'log',
    '--reverse', // oldest first: the replay depends on commit order
    '--pretty=format:',
    '--name-status',
    '--find-renames',
    'HEAD',
    '--',
    _specsDir,
    _adrDir,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'git log failed, so the history guards cannot run: ${result.stderr}',
  );
  final output = result.stdout as String;
  // Secondary sanity check, now that shallowness is ruled out above: a full
  // history that still shows no record at all means the query itself is wrong.
  expect(
    output.trim(),
    isNotEmpty,
    reason: 'git history shows no spec or ADR files ever committed, which '
        'cannot be true of a full clone of this repository',
  );
  return output;
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
      final verdict = replayRecordHistory(const [
        RecordEvent.added('0009', '0009-old-slug.md'),
        RecordEvent.renamed('0009', '0009-old-slug.md', '0009-new-slug.md'),
      ]);

      expect(verdict.vanished, isEmpty);
      expect(verdict.reused, isEmpty);
    });

    test('a_removed_number_reads_as_a_deletion', () {
      final verdict = replayRecordHistory(const [
        RecordEvent.added('0001', '0001-one.md'),
        RecordEvent.added('0002', '0002-two.md'),
        RecordEvent.deleted('0002', '0002-two.md'),
      ]);

      expect(verdict.vanished, ['0002']);
      expect(verdict.reused, isEmpty);
    });

    test('a_number_deleted_and_later_reassigned_is_reported_as_reuse', () {
      // The incident the rule exists for: 0009 removed, then handed to an
      // unrelated record. Comparing sets sees 0009 before and after and reports
      // nothing, which is why the guard replays events instead.
      final verdict = replayRecordHistory(const [
        RecordEvent.added('0009', '0009-benchmark.md'),
        RecordEvent.deleted('0009', '0009-benchmark.md'),
        RecordEvent.added('0009', '0009-something-else.md'),
      ]);

      expect(verdict.reused, ['0009']);
      // It is present again, so it is not also reported as vanished.
      expect(verdict.vanished, isEmpty);
    });

    test('reuse_staged_as_add_before_delete_is_still_reported', () {
      // git emits a single commit's statuses in path order, so a replacement
      // whose new slug sorts first arrives as add-then-delete. The number is
      // never empty at the add, so watching for that moment misses it.
      final verdict = replayRecordHistory(const [
        RecordEvent.added('0009', '0009-benchmark.md'),
        RecordEvent.added('0009', '0009-alternative.md'),
        RecordEvent.deleted('0009', '0009-benchmark.md'),
      ]);

      expect(verdict.reused, ['0009']);
      expect(verdict.vanished, isEmpty);
    });

    test('a_deleted_record_restored_under_its_own_slug_is_not_reuse', () {
      final verdict = replayRecordHistory(const [
        RecordEvent.added('0009', '0009-benchmark.md'),
        RecordEvent.deleted('0009', '0009-benchmark.md'),
        RecordEvent.added('0009', '0009-benchmark.md'),
      ]);

      expect(verdict.reused, isEmpty);
      expect(verdict.vanished, isEmpty);
    });

    test('git_status_lines_are_parsed_into_ordered_events', () {
      final events = parseHistory(
        'A\tdocs/specs/0009-old.md\n'
        'R100\tdocs/specs/0009-old.md\tdocs/specs/0009-new.md\n'
        'M\tdocs/specs/0009-new.md\n'
        'D\tdocs/specs/0009-new.md\n'
        'A\tdocs/adr/0001-elsewhere.md\n',
        _specsDir,
      );

      expect(events.map((e) => e.status).toList(), ['A', 'R', 'D']);
      // The ADR line belongs to another directory and is filtered out.
      expect(events.every((e) => e.number == '0009'), isTrue);
      expect(replayRecordHistory(events).vanished, ['0009']);
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
      final history = _historyOutput();

      expect(
        replayRecordHistory(parseHistory(history, _specsDir))
            .vanished
            .where((n) => !retiredSpecNumbers.containsKey(n)),
        isEmpty,
        reason: 'a spec number was deleted rather than retired in place',
      );
      expect(
        replayRecordHistory(parseHistory(history, _adrDir))
            .vanished
            .where((n) => !retiredAdrNumbers.containsKey(n)),
        isEmpty,
        reason: 'an ADR number was deleted rather than retired in place',
      );
    });

    test('no_number_was_deleted_and_reassigned_unless_allowlisted', () {
      final history = _historyOutput();

      expect(
        replayRecordHistory(parseHistory(history, _specsDir))
            .reused
            .where((n) => !renamedWithRewriteSpecNumbers.containsKey(n)),
        isEmpty,
        reason: 'a spec number was reassigned to a different record; if this is '
            'a rename whose rewrite defeated git similarity detection, add it '
            'to renamedWithRewriteSpecNumbers with a reason',
      );
      expect(
        replayRecordHistory(parseHistory(history, _adrDir))
            .reused
            .where((n) => !renamedWithRewriteAdrNumbers.containsKey(n)),
        isEmpty,
        reason: 'an ADR number was reassigned to a different record',
      );
    });

    test('the_allowlists_state_their_reasons', () {
      expect(allowlistEntriesWithoutReason(retiredSpecNumbers), isEmpty);
      expect(allowlistEntriesWithoutReason(retiredAdrNumbers), isEmpty);
      expect(
        allowlistEntriesWithoutReason(renamedWithRewriteSpecNumbers),
        isEmpty,
      );
      expect(
        allowlistEntriesWithoutReason(renamedWithRewriteAdrNumbers),
        isEmpty,
      );
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
