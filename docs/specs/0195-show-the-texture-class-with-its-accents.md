# SPEC: fix(ui): show the texture class with its pt-BR accents

## Problem

Every surface that names a texture class shows the classifier contract's identifier, so the user reads "Media" and "Muito Argilosa" where pt-BR product copy needs "Média" and "Muito argilosa" (#428).

## Scope

- Includes:
  - `SoilTextureReference.labelFor`, which maps a contract class name to its display label and returns any name it does not know unchanged. It lives in the file the texture-class literal guard already permits (SPEC 0194).
  - `SoilRecord.displayTextureClass` reads the label. Through it, these surfaces show the label:
    - the result header and `InfoSection`;
    - `AnalysisTile`, both its row text and its semantics label;
    - home's last analysis;
    - compare;
    - the shared text built by `share_content_builder.dart`.
  - The capture preview's classification chip and the history filter chips show the label. The filter still selects by the contract name.
- Does NOT include:
  - Any change to what is stored or sent: the `texture_class` column, the sync payload, the inference result, the corpus keys and the colour keys keep the contract name.
  - The CSV export (open PR #425), which is not on this branch. Its column stays the contract name, as a data export.
  - Accents in any other copy, or a rename of the contract's classes (`ml/config.yaml`, `assets/models/spec.json`).

## Acceptance Criteria

- `label_for_accents_the_contract_names`: `labelFor` returns "Média" for `Media` and "Muito argilosa" for `Muito Argilosa`, and returns `Arenosa`, `Argilosa` and an unknown name unchanged.
- `display_texture_class_uses_the_label`: a record classified `Media` displays "Média" and keeps `textureClass == 'Media'`; an unclassified record still displays "Não classificado".
- `result_header_shows_the_label`: the result screen for a `Media` record shows "Média" and no "Media".
- `analysis_tile_announces_the_label`: the history row for a `Muito Argilosa` record shows "Muito argilosa" and its semantics label starts with "Muito argilosa".
- `capture_chip_shows_the_label`: the capture preview's chip for a `Media` result reads "Média · NN%".
- `filter_chip_shows_the_label_and_filters_by_name`: the history filter chip reads "Média", and selecting it sets the filter to `Media`.
- `shared_text_uses_the_label`: the shared text names the class as "Média".
- `no_texture_class_literal_in_lib` still passes.
