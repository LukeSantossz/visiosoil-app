# SPEC: fix(ui): count the collection in the classes the model classifies

## Problem

The collection counts classes the classifier can never return, so it reads "0/12" forever.

- **The counter never moves (D8).** Home, Perfil and the history summary count each record's class against `SoilTextureColors.referenceClasses`, the twelve USDA texture names ("Argila", "Franco-argilosa" and so on), as SPEC 0203 and SPEC 0204 decided.
  - The model emits the released contract's classes: today `Arenosa`, `Media`, `Muito Argilosa` and `Argilosa` (`assets/models/spec.json`, ADR 0016).
  - None of them is a USDA name, so the intersection is empty for every real record. Home and Perfil read "0/12", and the summary reads "0/12 classes".
  - The history's Coleção grid lists the twelve USDA names, and none can ever be marked earned.
  - The test `collection earns only exact USDA reference labels` pins this behaviour: a record classified `Argilosa` earns nothing.
- **The total is not what the app classifies.** The app classifies four classes, and "/12" promises eight it cannot reach.
- **Counts read wrongly at one (D13).** Several counters write the plural whatever the number is:
  - Perfil: "1 análises e 1 classes guardadas neste aparelho";
  - the export sheet: "1 análises em uma planilha CSV.";
  - the "análises nesta semana" semantics labels on Home and in the history summary.

## Design Decision

**The collection is the contract's classes: its numerator is the classes the records hold among them, and its denominator is how many the contract has.**

- **One source for the list.** A `contractClassesProvider` resolves to the released contract's classes, in the contract's order.
  - It reads them through `InferenceService`, by awaiting `initialize()` and taking `contract.classes`, so the contract is parsed in one place.
  - No class name is written under `lib/` for this. A future contract that adds a class, such as Siltosa (ADR 0016), grows the collection without a code change.
- **The counters.** Home's "coleção" card, Perfil's "coleção" card and the history summary's "classes" cell read `N/T`.
  - `N` is the number of distinct classes that classified, live records hold among the contract's classes.
  - `T` is the number of contract classes, which is 4 today.
  - Their semantics labels read "N de T classes na coleção".
- **The Coleção grid** lists the contract's classes, in its order, under the label `SoilTextureReference.labelFor` gives them ("Média", "Muito argilosa").
  - A class is earned when a record holds that exact contract name.
  - Its tint stays `SoilTextureColors.forClass`, which already keys these names.
- **While the classes are not known.** While the provider loads, or if the contract fails, the counter reads "—", which is the stat cells' existing "no value" mark. The grid shows no tiles.
  - The contract is a build-time fact that `class_list_test.dart` checks against `ml/config.yaml`, so the failure case is a broken build, not a field state.
- **Plurals.** A count of exactly one takes the singular: "1 análise", "1 classe". Every other count, zero included, takes the plural, as pt-BR does.
  - One helper, `Formatters.count(n, singular, plural)`, writes the number and the noun.
  - It applies to the four strings above. The offline banner already reads "1 análise aguarda", and keeps its own wording.

## Alternatives Considered

- **Map each contract class to the USDA names it spans and keep "/12".** Rejected. The model returns no fractions (redesign v11 §11), so a class like `Media` cannot say which of its USDA names a sample is. A tile earned by inference would claim a measurement nobody made.
- **Write the four names as a constant beside the colours.** Rejected. The class list would then live twice, in the contract and in code, and the counter would drift the day a contract changes it. SPEC 0083 makes the contract the class list.
- **Order the grid by grain size (Arenosa → Muito argilosa) instead of the contract's order.** Rejected for now. The order would need class names in code, which is the drift above. The contract's order is the one every other class list in the app follows.

## Scope

- Includes:
  - `contractClassesProvider`;
  - the collection's count in `stats_grid.dart`, `history_list.dart` (summary and Coleção grid) and `profile_screen.dart`;
  - `Formatters.count`, and the four plural strings in `profile_screen.dart`, `export_sheet.dart`, `stats_grid.dart` and `history_list.dart`;
  - their tests, including replacing `collection earns only exact USDA reference labels`.
- Does NOT include:
  - the texture triangle and the USDA reference colours and names in `SoilTextureColors.referenceClasses`, which stay as visual reference;
  - `SoilTextureColors.forClass`'s fallback to the reference map;
  - the mock PNGs that draw "7/12", which predate the four-class model;
  - the rest of the audit (D5, D6, D7, D9, D10, D11, D12).

## Acceptance Criteria

- `contract_classes_come_from_the_contract`: `contractClassesProvider` resolves to the classes of `assets/models/spec.json`, in its order.
- `collection_counts_contract_classes`: with records classified `Argilosa`, `Argilosa` and `Media`, and one record with no classification:
  - Home's collection card reads "2/4", with the semantics label "2 de 4 classes na coleção";
  - Perfil's collection card reads "2/4", with the semantics label "2 de 4 classes na coleção";
  - the history summary reads "2/4".
- `collection_ignores_names_outside_the_contract`: a record whose class is a USDA name ("Argila") adds nothing to the count and earns no tile.
- `collection_grid_lists_contract_classes`: the Coleção grid holds exactly four tiles: "Arenosa", "Média", "Muito argilosa" and "Argilosa", in that order. "Argilosa, conquistada" and "Média, conquistada" are announced, and the other two read "não conquistada".
- `collection_without_contract_reads_a_dash`: when the provider fails, the counters read "—" and nothing throws.
- `counts_take_the_singular_at_one`:
  - with one record and one class, Perfil reads "1 análise e 1 classe guardadas neste aparelho", and the export sheet reads "1 análise em uma planilha CSV.";
  - with zero and with two, they read the plural.
- `Formatters.count` returns "0 análises", "1 análise" and "2 análises".
- Existing tests pass, with the "/12" expectations in the Home, history, profile and main-tabs tests updated to the contract's total.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **The collection needs the contract parsed before it can show a number.** Home now triggers `InferenceService.initialize()` at first paint, not at the first capture. Parsing is one asset read; it is lazy today and stays idempotent.
- **"—" is shown until it resolves.** On a cold start the counter may read "—" for a frame or two before "N/4".
- **Plurals cover only "1".** pt-BR also writes "1,5", but no counter here holds a fraction.
- **A record saved under an older contract keeps that contract's name.** If a future contract renames a class, the old records stop counting toward the collection. No such rename exists or is planned.
