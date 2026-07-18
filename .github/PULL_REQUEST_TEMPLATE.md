<!-- markdownlint-disable MD041 -->
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
- **Closes:** <!-- "Closes #N" for every issue this PR completes, or "none (no issue)". GitHub only closes the issue when this keyword is present. -->

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
- [ ] Every issue this PR completes is listed under **Closes** with the `Closes #N` keyword, so it closes on merge instead of lingering open.
- [ ] Spec approved at the Gate before implementation, and the change matches its Scope (per `spec_method.md`).
- [ ] Each Acceptance Criterion has a passing test; tests were written before their implementation.
- [ ] Commented-out code and unnecessary debug statements removed.
- [ ] Code follows the project style guide.
- [ ] New dependencies work without breaking the build.
- [ ] Review layers recorded: R1 internal review; R2 cross-provider review when a second-provider reviewer is available, otherwise R1 plus the human PR review stand in for R2 and the absence is noted here; R3 automated PR review where applicable. Name the Author and Reviewer models (per `ai_guidelines.md` Review Composition) and note any layer that did not run and why.
