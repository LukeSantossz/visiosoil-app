# SPEC: docs(privacy): publish the privacy policy and the account deletion page

## Problem

Google Play needs a privacy policy at a public URL for an app that requests the
camera and precise location and offers Google sign-in, and a web page where a
user can learn how to delete their account without the app (#276, #278).
VisioSoil has neither, and the repository serves no web page at all.

## Design Decision

**Two static pages in Brazilian Portuguese live in `site/` on `main`, and a
workflow publishes that directory to GitHub Pages on every push to `main` that
touches it.**

**The pages:**

- `site/privacidade.html` is the privacy policy.
- `site/excluir-conta.html` explains how to delete the account and the data,
  with or without the app.
- Plain HTML with a small inline stylesheet, `lang="pt-BR"`, and no script, font
  or request to any other origin. A page about privacy should not load a tracker
  to say so.
- Their URLs are
  `https://lukesantossz.github.io/visiosoil-app/privacidade.html` and
  `https://lukesantossz.github.io/visiosoil-app/excluir-conta.html`. SPEC 0157
  links the first from Settings.

**What the policy states, each item as the build does it today:**

- **Who.** The controller is Lucas Gonçalves, the developer, with a contact
  e-mail for data requests, `visiosoilapp@gmail.com`, which the Developer created
  on 2026-10-14.
- **What stays on the device.** The photographs, the coordinates and their
  accuracy, the address, the texture result, the field and sample names, and
  the management tips are stored only on the phone. There is no VisioSoil
  server.
- **What leaves the device, and when:**
  - When a capture has a location fix, the address is looked up before the
    record is saved, by the system's geocoding service, which sends the
    coordinates to Google.
  - Google sign-in gives the app the user's name and e-mail, which the app keeps
    on the phone in secure storage. Sign-in is optional.
  - A share sends what the user chooses, to whom the user chooses. The location
    goes only when the user turns it on for that share (ADR 0007).
  - The error report leaves the phone only when the user shares it from
    Settings (SPEC 0110). It names the app and system versions, and no device
    identifier or account. Coordinates, e-mails and tokens are redacted, but it
    may carry fragments of an error message, which can include an address, as
    SPEC 0110's Risks require the policy to say.
- **What is removed or excluded.** The camera's metadata (EXIF) is stripped from
  each stored JPEG, except its orientation; a JPEG the parser cannot read is
  stored as it came (ADR 0005). Android's backup
  and device-to-device transfer do not copy the app's data (ADR 0006).
- **No analytics, no advertising,** and no sale or sharing of data with third
  parties beyond the two Google services above.
- **Permissions.** Camera to photograph the sample; location, optional, to place
  the record. Each is asked when capture needs it.
- **Deletion and rights.** "Apagar todos os dados" erases the records and the
  error report; "Excluir conta" removes the session and revokes the app's Google
  grant (SPEC 0113); uninstalling removes everything. The LGPD rights of the
  data subject (art. 18) are listed, and the contact handles any request.
- **Children.** The app is a tool for agronomists and is not directed at
  children.
- **Changes.** The page carries the date it took effect, and a change is
  published at the same URL.

**What the deletion page states.** With no server, the account is the session
on the phone plus the grant Google holds. A user with the app uses "Excluir
conta". A user without it revokes the grant at
`myaccount.google.com/connections`, and uninstalling the app erased the rest.
Nothing is kept anywhere else, so there is nothing for a request to the contact
to erase beyond what those steps remove; the contact still answers questions.

**The workflow.** `.github/workflows/pages.yml` runs on a push to `main` that
touches `site/**` or the workflow itself, and on `workflow_dispatch`. It uploads
`site/` alone with `actions/upload-pages-artifact` and deploys it with
`actions/deploy-pages`, each action pinned to a commit SHA as `ci.yml`'s
`corpus-tests` job pins its own. Its token has `contents: read`, `pages: write`
and `id-token: write`, and nothing else. It runs on no pull request, and the job
runs only when `github.ref` is `refs/heads/main`, because `workflow_dispatch`
can be started from any branch; so a branch cannot publish. The checkout keeps
no credentials, as every checkout in `ci.yml` does. Pages is switched on with the GitHub Actions source once, by
`gh api`, as the Developer chose.

## Alternatives Considered

- **Serve `docs/` from `main` with Pages' branch source.** Rejected. It would
  publish every spec, ADR and study as a web page, and the policy's URL would sit
  among them.
- **A `gh-pages` branch.** Rejected. The policy would change outside the pull
  requests and review that every other user-facing text goes through.
- **Markdown rendered by Jekyll.** Rejected. Jekyll's theme loads assets the
  page does not need, and two short pages do not justify a build step.
- **A third-party policy generator or host.** Rejected. A generic text would
  claim things the build does not do, and #276 asks for what the audit verified.

## Scope

- Includes:
  - `site/privacidade.html` and `site/excluir-conta.html`.
  - `.github/workflows/pages.yml`.
  - A test, `test/site/site_pages_test.dart`, that reads the two pages and the
    workflow, in the way `test/android_proguard_rules_test.dart` reads its files.
  - Switching Pages on with the Actions source, by `gh api`, and recording the
    URLs on #276 and #278 once the first deploy serves them.
- Does NOT include:
  - The Settings link to the policy (#279, SPEC 0157).
  - The Play Data safety form (#293) or the store listing (#294).
  - An English version of either page.
  - Any change to the app's code, or to what the app collects.
  - A custom domain.
  - The google_sign_in 7 migration (#119).

## Acceptance Criteria

- `policy_names_the_controller_and_the_contact`: the policy names Lucas
  Gonçalves and the contact e-mail.
- `policy_says_records_stay_on_the_device`: the policy says the photographs,
  coordinates, address and texture result stay on the phone, and that there is
  no VisioSoil server.
- `policy_names_each_way_data_leaves_the_device`: the policy names the
  geocoding service and Google, Google sign-in with the name and e-mail, the
  share with location only on the user's choice, and the error report sent only
  by the user.
- `policy_says_there_is_no_analytics_or_advertising`.
- `policy_says_how_to_delete_and_links_the_deletion_page`: the policy names
  "Apagar todos os dados", "Excluir conta" and uninstalling, lists the LGPD
  rights, and links `excluir-conta.html`.
- `policy_carries_its_effective_date`.
- `deletion_page_works_without_the_app`: the deletion page names "Excluir
  conta", `myaccount.google.com/connections`, uninstalling, and the contact
  e-mail, and links back to the policy.
- `pages_load_nothing_from_another_origin`: neither page has a `<script>`, and
  every `src` or stylesheet `href` is relative.
- `pages_are_brazilian_portuguese`: both declare `lang="pt-BR"` and UTF-8.
- `workflow_publishes_only_site_from_main`: the workflow triggers on push to
  `main` and `workflow_dispatch` only, uploads `site`, and asks for exactly
  `contents: read`, `pages: write` and `id-token: write`.
- `workflow_pins_each_action_to_a_commit`: every `uses:` names a 40-character
  SHA.
- After merge, both URLs answer `200` over HTTPS. This one is checked by hand,
  since it needs the deploy, and is recorded on #276.
- `flutter analyze`, the full suite and `mf check` pass.

## Reproducibility

```sh
flutter test test/site/site_pages_test.dart
flutter analyze && flutter test && mf check
# after merge and the first deploy
curl -sI https://lukesantossz.github.io/visiosoil-app/privacidade.html
curl -sI https://lukesantossz.github.io/visiosoil-app/excluir-conta.html
```

## Risks and Assumptions

- **Assumption: the policy describes the Android build.** The iOS build exists
  only to keep CI honest; its backup exclusion is not configured, so the policy
  does not claim it.
- **Risk: the build changes and the policy does not.** Sync (#55), a reporting
  SDK or anything else that sends data would make the page wrong. The test pins
  the claims, not the code, so it cannot catch that; the review checklist of the
  change that adds such a path has to.
- **Risk: the text is not legal advice.** It states facts the code verifies. A
  lawyer's review, if wanted, is the Developer's call.
- **Assumption: `actions/configure-pages` is not needed.** `deploy-pages` takes
  the artifact directly; this is checked against the actions' READMEs at
  implementation, and added if they say otherwise.
