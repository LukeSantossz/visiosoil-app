# SPEC: chore(assets): keep documentation files out of the app bundle

## Problem

Every installed copy of VisioSoil carries two repository documents (#292), because `pubspec.yaml` declares `assets/models/` and `assets/corpus/` whole:
- `assets/corpus/README.md`;
- `assets/models/.gitkeep`, which still describes the TFLite model SPEC 0084 removed.

## Design Decision

**Declare what the app reads, and keep documents out of asset folders.**
- `pubspec.yaml` declares `assets/models/spec.json` as a file, instead of its folder. The contract is tracked (ADR 0012), so the folder needs no placeholder, and `assets/models/.gitkeep` is deleted.
- `assets/corpus/` stays declared as a folder. Its three files are build products that are absent until a corpus release exists, and Flutter fails the build on a declared file that is missing. Its README moves to `docs/architecture/corpus-assets.md`, beside the research agent's architecture documents. The empty `.gitkeep` stays, so the folder exists in a fresh clone.
- A test reads the `assets:` list from `pubspec.yaml`. It fails if any declared folder holds a Markdown file or a non-empty placeholder, so a document cannot slip back into the bundle.

## Alternatives Considered

- **Declare the corpus files one by one.** Rejected: the build would fail in every clone without a corpus release, which today is every clone.
- **Keep the folders and exclude the documents.** Rejected: `pubspec.yaml` has no exclude syntax for assets, so a declared folder ships everything in it.
- **Move the corpus README into `corpus/README.md`.** Rejected: that file documents the build that produces the assets, while this one documents the assets the app reads and how it tolerates their absence. A separate document under `docs/architecture/` keeps each one about one thing.

## Scope

- Includes:
  - `pubspec.yaml`: `assets/models/spec.json` replaces `assets/models/`.
  - `assets/models/.gitkeep`: deleted.
  - `assets/corpus/README.md` moves to `docs/architecture/corpus-assets.md`, with its paths adjusted to the new location.
  - `test/pubspec_assets_test.dart`, a new test.
- Does NOT include:
  - Fonts and branding images. Fonts are declared file by file, and `assets/branding/` is not declared as an asset.
  - The corpus artifacts and the 500 KB ceiling `asset_corpus_store_test.dart` enforces on their folder.
  - ADR 0012's text, which already calls `assets/models/.gitkeep` redundant once the contract is tracked.

## Acceptance Criteria

- `the_contract_is_declared_as_a_file`: the `assets:` list holds `assets/models/spec.json`, and no entry for the `assets/models/` folder.
- `no_declared_asset_folder_holds_a_document`: no folder in the `assets:` list holds a `.md` file, and any `.gitkeep` in one is empty.
- `every_declared_asset_file_exists`: each file entry in the list exists, so the build does not fail on a missing one.
- **Bundle check.** The release APK's `assets/flutter_assets/assets/` holds `models/spec.json` and `corpus/.gitkeep`, and no README and no `models/.gitkeep`.

## Reproducibility

`flutter test test/pubspec_assets_test.dart`, then `flutter build apk --release` and list the APK's `assets/flutter_assets/assets/` entries.

Flutter 3.44.1.

## Risks and Assumptions

- Assumes nothing else needs a file in `assets/models/` at run time. `InferenceService` reads only `spec.json`, and `ml/scripts/deploy_to_app.sh` copies only that file in. A future artifact there has to be added to `pubspec.yaml` by name, which this spec's test makes visible.
- An empty `.gitkeep` still ships, as a zero-byte file. Flutter has no way to declare a folder without bundling what it holds.
