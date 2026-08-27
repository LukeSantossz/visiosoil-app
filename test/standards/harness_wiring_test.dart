// Guards that the gates this repository adopted actually reach a clone.
//
// The guard this replaces did not exist, and the thing it guards has already
// failed twice in the two repositories that adopted the harness before this
// one: both staged their hooks `100644`, because `core.fileMode` is false on
// the Windows checkout that wrote them, and git skips a non-executable hook
// without a word. The repository then reports a wired gate and has none, on
// every platform except the one that adopted it.
//
// So the assertions below are about state this repository owns and git
// resolves. What is deliberately absent is any assertion about
// `core.hooksPath`: it is local git config, set per clone and never committed,
// so a fresh checkout — CI's included — has none, and a test demanding it would
// fail for the one reason that is not a defect. `scripts/setup.sh` is what sets
// it and `mf doctor` is what reports it, to the Developer whose clone it is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _hooksDir = '.githooks';
const _projectFile = '.framework.toml';
const _hooks = <String>['pre-push', 'commit-msg'];

/// The index entry for a path, or the empty string when it is untracked.
String _stagedEntry(String path) {
  final result = Process.runSync(
    'git',
    ['ls-files', '--stage', '--', path],
    workingDirectory: Directory.current.path,
  );
  return (result.stdout as String).trim();
}

void main() {
  group('the gates reach a clone', () {
    test('both hooks are versioned in this repository', () {
      for (final name in _hooks) {
        expect(
          File('$_hooksDir/$name').existsSync(),
          isTrue,
          reason:
              '$_hooksDir/$name is missing; `mf init` writes both gates here, '
              'and a hooks directory with only one of them enforces only one',
        );
      }
    });

    test('the index records both hooks as executable', () {
      for (final name in _hooks) {
        final entry = _stagedEntry('$_hooksDir/$name');
        expect(
          entry,
          isNotEmpty,
          reason: '$_hooksDir/$name is not tracked, so no clone receives it',
        );
        expect(
          entry.startsWith('100755'),
          isTrue,
          reason:
              'the index records $_hooksDir/$name as non-executable; git skips '
              'it on every platform that honours the bit. Run '
              '`git update-index --chmod=+x $_hooksDir/$name`',
        );
      }
    });

    test('a hook that cannot reach its runner refuses the push', () {
      // Executed rather than read: every pre-v0.5.0 hook ended its failure
      // paths with `|| exit 0` and printed nothing, and the current hook's own
      // comments quote that string while explaining why it is wrong — so
      // grepping for it matches the explanation instead of the behaviour.
      //
      // `MF_BIN` naming something that is not executable is the cheapest way to
      // reach the failure: it is the first branch of the runner lookup, so the
      // hook answers without a repository state to arrange.
      for (final name in _hooks) {
        final result = Process.runSync(
          'bash',
          // Repo-relative and slash-separated: bash is handed the path
          // verbatim, and a Windows absolute path arrives with its separators
          // eaten as escapes.
          ['$_hooksDir/$name', 'HEAD'],
          workingDirectory: Directory.current.path,
          environment: {'MF_BIN': 'no-such-runner-anywhere'},
        );
        expect(
          result.exitCode,
          isNot(0),
          reason:
              '$_hooksDir/$name exited 0 with an unusable runner; a gate that '
              'cannot run has not passed, it has not run',
        );
        expect(
          result.stderr as String,
          contains('MF_BIN'),
          reason:
              '$_hooksDir/$name refused without saying why; a silent refusal '
              'is the failure mode this hook was rewritten to end',
        );
      }
    });
  });

  group('the gates read what the submodule supplies', () {
    late final String policy;

    setUpAll(() => policy = File(_projectFile).readAsStringSync());

    test('no second standards corpus exists beside the submodule', () {
      expect(
        Directory('docs/standards').existsSync(),
        isFalse,
        reason:
            'a second corpus exists beside the submodule; the two drift, and '
            'only one of them is updated by `git submodule update`',
      );
      expect(
        File('.standards/docs/standards/INDEX.md').existsSync(),
        isTrue,
        reason:
            '.standards is not checked out; run `git submodule update --init`. '
            'Every gate reads the corpus it supplies',
      );
    });

    test('the paths name the submodule', () {
      expect(
        policy,
        contains('standards = ".standards/docs/standards"'),
        reason:
            'paths.standards does not name the submodule, so the gates read a '
            'corpus this repository would have to maintain itself',
      );
      expect(
        policy,
        contains('agents_source = ".standards/docs/agents/instructions.md"'),
        reason:
            'paths.agents_source does not name the submodule, so `mf agents '
            'sync` generates from a source this repository does not have',
      );
    });

    test('the R2 chain names a reviewer that is defined', () {
      // A chain nobody fills reports "R2 did not run" on every push, forever.
      final chain = RegExp(r'\[roles\.r2\]\s*\nbackends = \[([^\]]*)\]')
          .firstMatch(policy);
      expect(chain, isNotNull, reason: 'roles.r2 declares no backend chain');
      final named = RegExp('"([^"]+)"')
          .allMatches(chain!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(
        named,
        isNotEmpty,
        reason: 'roles.r2.backends is empty, so R2 never runs. That is honest, '
            'not a gate',
      );
      for (final name in named) {
        expect(
          policy,
          contains('[backends.$name]'),
          reason:
              'the R2 chain names "$name" and nothing defines it; the runner '
              'reports an unknown backend rather than reviewing',
        );
      }
    });
  });

  group('the instruction files are generated, not written', () {
    test('this repository owns the overlay the generated files carry', () {
      expect(
        File('docs/agents/project.md').existsSync(),
        isTrue,
        reason:
            'docs/agents/project.md is missing; it is where everything this '
            'project must tell an agent lives, since the framework source it '
            'is appended to is inside the submodule and not ours to edit',
      );
      expect(
        File(_projectFile).readAsStringSync(),
        contains('agents_overlay = "docs/agents/project.md"'),
        reason:
            'paths.agents_overlay does not name the overlay, so `mf agents '
            'sync` drops every project-specific instruction from CLAUDE.md '
            'and AGENTS.md',
      );
    });

    test('the generated files say they are generated', () {
      for (final name in ['CLAUDE.md', 'AGENTS.md']) {
        expect(
          File(name).readAsStringSync(),
          contains('mf agents sync'),
          reason:
              '$name carries no generation header, so it was hand-written and '
              '`mf check agents` will report it as drift',
        );
      }
    });
  });
}
