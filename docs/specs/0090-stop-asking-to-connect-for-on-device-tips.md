# SPEC: fix(research): stop telling an offline user to connect when tips compose on the device

## Problem

Offline, the management-tips section replaces its "Gerar dicas" action with
"Sem conexão — Conecte-se à internet para gerar dicas de manejo." and disables
the retry and the refresh. Yet tips compose on the device from the corpus the
app holds and need no network (ADR 0022), so the section refuses work it could
do and tells the user something false (#283).

## Scope

- Includes:
  - `lib/core/features/details/management_tips_section.dart` stops watching
    connectivity:
    - the empty state always offers "Gerar dicas";
    - a failed first generation always offers its retry;
    - cached tips always offer "Atualizar dicas".

    The "Sem conexão" empty state and the `online` parameter of the data view
    are removed.
  - `test/features/details/management_tips_section_test.dart`: the test that
    pinned the offline refusal is replaced by the criteria below.
- Does NOT include:
  - `ConnectivityService` and its providers. They stay for the corpus refresh,
    the one place where being offline does mean "cannot refresh", and which has
    no release endpoint yet. The overrides in `details_screen_test.dart` stay
    with them.
  - The proxy-era messages in `_messageFor`. `ResearchFailureKind` is shared
    with `ProxyResearchService`, which still has those failure kinds.
  - The disclaimer literal the section repeats from `AppStrings`.
  - Whether the section appears at all before a record can be classified,
    which #281 and ADR 0026 govern.

## Acceptance Criteria

- `offline_empty_cache_offers_generate_tips`: offline and with nothing cached,
  the section shows "Gerar dicas", and no text asks the user to connect.
- `offline_generate_composes_tips`: offline, tapping "Gerar dicas" runs the
  research service and the composed tips render.
- `offline_failed_generation_offers_retry`: offline, a failed first generation
  shows its message with a retry that runs the service again.
- `offline_cached_tips_offer_refresh`: offline, cached tips show an enabled
  "Atualizar dicas".
