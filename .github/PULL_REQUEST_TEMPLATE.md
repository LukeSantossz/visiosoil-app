<!--
Title: Conventional Commits format, type from the Type Table in
.standards/docs/standards/github.md (e.g. feat(auth): implement password recovery).
Labels: add one type label (feat, fix, ...) and one complexity label (patch, minor, major).
Replace every HTML comment below with real content before requesting review.
-->

## 1. Context

- **Motivation:** <!-- reason for the change -->
- **Task Link:** <!-- tracker URL, or "none (no tracker in use)" -->
- **Spec Link:** <!-- link to the approved SPEC for this change, or "none (trivial change)" -->

## 2. What Was Done

<!-- list the technical changes in summary form -->

## 3. How to Test

1. Check out the branch.
2. Install dependencies: `flutter pub get` (run `dart run build_runner build --delete-conflicting-outputs` if DB tables changed).
3. Run the checks: `flutter analyze && flutter test`.
4. Verify the build runs without errors.

## 4. Evidence

<!-- screenshots or videos if the change is visual; omit this section if backend or configuration only -->

## 5. Self-Review Checklist

- [ ] Self-review done in the Files Changed tab.
- [ ] Spec approved at the Gate before implementation, and the change matches its Scope (per `spec_method.md`).
- [ ] Each Acceptance Criterion has a passing test; tests were written before their implementation.
- [ ] Commented-out code and unnecessary debug statements removed.
- [ ] Code follows the project style guide.
- [ ] New dependencies work without breaking the build.
- [ ] Review layers recorded: R1 internal review, R2 cross-provider review, R3 automated PR review where applicable, with Author and Reviewer models named (per `ai_guidelines.md` Review Composition). Note any layer that did not run and why.
