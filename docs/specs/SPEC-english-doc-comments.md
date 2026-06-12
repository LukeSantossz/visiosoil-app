# SPEC: docs(lib): translate doc comments to english

## Problem

103 comment lines across 24 Dart files in `lib/` and `test/` are written in Portuguese, violating the Language rule of `code_conventions.md` and the project's own `CLAUDE.md` convention that code comments are English.

## Design Decision

Translate every Portuguese comment (`///` dartdoc and `//` inline) in `lib/` and `test/` to precise technical English, preserving meaning, dartdoc structure (`[references]`, code spans), formatting, indentation, and comment placement. String literals (pt-BR user-facing product copy, exempt per `CLAUDE.md`), identifiers, and executable code remain byte-identical. Specs for parallel changes live under `docs/specs/`; the root `SPEC.md` remains the merged adoption spec.

## Alternatives Considered

- **Delete low-value comments instead of translating:** rejected — judging comment value is a separate cleanup with its own criteria; mixing it in makes this mechanical language alignment unreviewable.
- **Translate gradually as files get touched:** rejected — leaves the codebase mixed-language indefinitely and spreads translation noise across unrelated future PRs.

## Scope

- Includes:
  - Comment text in `lib/**/*.dart` and `test/**/*.dart` (24 files identified by sweep, plus any residual Portuguese comments found during review).
- Does NOT include:
  - Any change to string literals, identifiers, or executable code.
  - Adding, removing, or rewording comments beyond translation.
  - Fixing the address-sentinel mismatch listed in Known Technical Debt.
  - README or other documentation files (already English).

## Acceptance Criteria

- `no_accented_comment_chars_remain`: searching `lib/` and `test/` for comment lines containing accented characters returns zero matches.
- `no_unaccented_portuguese_comments_remain`: a manual sweep for accent-free Portuguese comment lines (e.g. "registro", "tela", "nao") returns none.
- `strings_and_code_unchanged`: the diff touches only comment text — no string literal, identifier, or statement changes (verified line-by-line in review).
- `analyzer_and_tests_unaffected`: `flutter analyze` and `flutter test` pass on CI exactly as on `main`, since comments cannot change semantics.

## Reproducibility

```bash
grep -rEn --include='*.dart' '//.*[áéíóúâêôãõç]' lib test | wc -l   # expect 0
flutter analyze && flutter test                                      # via CI on the PR
```

No randomness involved.

## Risks and Assumptions

- Translation fidelity is the main risk; mitigated by line-by-line diff review against the originals before the PR opens.
- Assumes comments are the only non-string Portuguese content in the Dart sources (the accent sweep plus a stop-word sweep verify this).
- Dartdoc `[symbol]` references and code spans are preserved verbatim, so generated docs links are unaffected.
