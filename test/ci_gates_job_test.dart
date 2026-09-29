import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the `gates` job (#201, SPEC 0085): CI runs the same `mf check` the
/// hooks run, so a clone that never wired `core.hooksPath` still meets the
/// gates.
///
/// Asserts executable tokens scoped to the job and to its steps, as
/// `ci_ios_build_test.dart` does for `build-ios`. Whole-line YAML comments are
/// stripped first, so a token surviving only in a comment cannot keep the
/// guard green.
void main() {
  final ci = File('.github/workflows/ci.yml')
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');

  /// The text of the `gates` job, up to the next job at the same indentation.
  String gatesJob() {
    final start = ci.indexOf('\n  gates:\n');
    expect(start, isNot(-1), reason: 'the gates job is missing from ci.yml');
    final next = RegExp(
      r'\n  [a-z][a-z0-9-]*:\n',
    ).firstMatch(ci.substring(start + 1));
    return next == null
        ? ci.substring(start)
        : ci.substring(start, start + 1 + next.start);
  }

  /// One step of the `gates` job, found by its `name:`.
  String step(String name) {
    final job = gatesJob();
    final start = job.indexOf('- name: $name');
    expect(start, isNot(-1), reason: 'the gates job has no step "$name"');
    final end = job.indexOf('\n      - ', start + 1);
    return end == -1 ? job.substring(start) : job.substring(start, end);
  }

  bool runsLine(String text, String command) => RegExp(
    '^\\s*${RegExp.escape(command)}\\s*\$',
    multiLine: true,
  ).hasMatch(text);

  group('ci gates job', () {
    test('the_gates_job_runs_mf_check_on_a_pull_request', () {
      final job = gatesJob();
      expect(
        job,
        contains('fetch-depth: 0'),
        reason:
            'the spec, commit and branch gates read the range between '
            'the base and the head, and a shallow clone has neither end',
      );
      expect(
        job,
        contains('submodules: recursive'),
        reason: 'the gates read the standards the submodule supplies',
      );
      expect(job, contains('persist-credentials: false'));

      final pullRequest = step('Gates (pull request)');
      expect(pullRequest, contains("if: github.event_name == 'pull_request'"));
      expect(
        pullRequest,
        contains(r'git switch --force-create "$HEAD_REF" "$HEAD_SHA"'),
        reason:
            'actions/checkout leaves a pull request on a detached '
            'HEAD, where the branch gate fails over a name nobody chose',
      );
      expect(
        pullRequest,
        contains(r'git branch --force "$BASE_REF" "origin/$BASE_REF"'),
      );
      expect(
        runsLine(pullRequest, 'mf check'),
        isTrue,
        reason: 'a pull request runs every gate the pre-push hook runs',
      );
    });

    test('the_gates_job_runs_the_tree_gates_on_any_other_event', () {
      final other = step('Gates (no pull request)');
      expect(other, contains("if: github.event_name != 'pull_request'"));
      expect(
        runsLine(other, 'mf check docs records agents design'),
        isTrue,
        reason:
            'with no branch under review, the gates that remain are '
            'the four that read the tree',
      );
    });

    test('the_gates_job_installs_the_locked_mf_version', () {
      final job = gatesJob();
      expect(
        job,
        contains('contents: read'),
        reason: 'the job needs no write access to the repository',
      );

      final install = step('Install mf at the locked version');
      for (final token in [
        '.framework.lock',
        'framework_version',
        'releases/download/',
        'linux_amd64',
        'SHA256SUMS',
        'sha256sum -c',
        'mf version',
        'GITHUB_STEP_SUMMARY',
      ]) {
        expect(
          install,
          contains(token),
          reason: 'the install step does not use "$token"',
        );
      }
    });
  });
}
