# SPEC: feat(observability): keep a local report of uncaught errors the user can share

## Problem

Release builds have no way to tell the maintainer that something went wrong on
a user's phone (#287).

- There is no `FlutterError.onError`, no `PlatformDispatcher.instance.onError`
  and no reporting SDK.
- Android vitals reports native crashes and ANRs, but an uncaught Dart exception
  is neither, so a broken screen in the field is invisible.
- The app logs through `dart:developer`, which a release build does not
  surface.

On 2026-10-02 the Developer chose the **local-only** sink from the three #287
weighed: errors are written to a file on the device, and the user shares it from
Settings. No data leaves the device unless the user sends it.

## Design Decision

**An `ErrorReportStore` appends each uncaught Dart error to a capped file in
the app's support directory, and Settings shares that file through the share
sheet.**

**What an entry holds:**

- the UTC time;
- the source, `framework` or `platform`;
- the error's runtime type;
- for a framework error, the library `FlutterErrorDetails` names, such as
  "widgets library";
- the error's message, redacted and cut to 300 characters;
- the stack trace.

**The message is kept because the Developer chose it at the Spec Gate on
2026-10-02, for what it tells a reader about the input that failed.** A message
can also echo that input. A `FormatException` quotes it, and SPEC 0012 found
exactly that leaking a session blob into logs. So before it is written, a
message is redacted:

- every decimal number with three or more fractional digits becomes
  `<number>`. `Formatters.coordinates` writes six, and a raw `double` writes
  more, so a coordinate cannot survive in either form;
- `ya29.` OAuth tokens, JWTs (`eyJ…` in three dot-separated parts) and any
  unbroken run of 24 or more letters, digits, `-`, `_`, `+`, `/` or `=` become
  `<token>`;
- email addresses become `<email>`.

Then it is cut to 300 characters, which bounds how much input any one message
can carry.

**An address is the residual risk, and the Developer accepted it.** An address
is free text, and no pattern reliably finds it, so one quoted in a message can
survive redaction, inside those 300 characters. It reaches nobody unless the
user shares the report. The framework's context description stays out, because
it can print a widget's fields at any length.

**The file:**

- It is `error_report.txt` in `getApplicationSupportDirectory()`. The directory
  is private to the app, and ADR 0006 excludes it from OS backup and device
  transfer.
- It is capped at the newest 50 entries. Recording the 51st drops the oldest,
  so the file stays small and readable.
- When shared, the text starts with a header that names the app's version and
  build (from `package_info_plus`) and the OS version string. It names no
  device identifier and no account.

**The hooks:**

- They are installed by `installErrorReporting(store)` in `main()`, before
  `runApp`.
- `FlutterError.onError` records the error, then calls the handler it replaced,
  so debug builds still print and show the red screen.
- `PlatformDispatcher.instance.onError` records the error, then returns
  `false`, which leaves the engine's default reporting in place. An uncaught
  Dart error does not end the process either way.
- **Recording never throws out of a handler.** A throw there would recurse, or
  replace the original error. The store's write catches everything, which
  `code_conventions.md` allows at a boundary, and an error handler is the
  outermost one. It logs the failure's type through `dart:developer`.
- Writes are queued, so two errors arriving together cannot interleave.

**Settings:**

- An "Relatório de erros" row shares the report through `share_plus`, as a file
  with a one-line caption.
- It is enabled only when the report holds an entry, and otherwise reads that
  there is nothing to send.
- Its subtitle says that nothing leaves the phone unless it is shared.
- "Apagar todos os dados" also clears the report, because the report is data
  the app keeps.

**What this feeds:**

- The Data safety answers (#293) declare no crash data collected, because
  nothing is transmitted without a user action.
- The privacy policy (#276) describes the optional report the user may send,
  and what it contains.

**Sequencing:** the other session's dark theme (SPEC 0107) rewrites `main.dart`
and the Settings screen. The store and its tests come first; the wiring into
`main.dart` and Settings follows once 0107 has merged into `main`.

## Alternatives Considered

- **Firebase Crashlytics or Sentry.** Declined by the Developer for v1. Each
  transmits device data automatically, which adds a third party, a Data safety
  declaration and a privacy-policy section. Each also needs a project, plus
  `google-services.json` or a DSN.
- **Leave the message out.** This was the recommendation at the Gate, and the
  Developer declined it. It is the only rule that guarantees no address
  reaches the file, but it costs the report the one field that names the
  failing input. With redaction and the cut, the remaining exposure is an
  address in a report the user chooses to send.
- **An in-app viewer for the report.** Deferred. Sharing the file serves the
  one reader the report has, the maintainer, and a viewer adds a screen to
  design and test.
- **Return `true` from `PlatformDispatcher.onError`.** Rejected. It would
  silence the console in debug builds, where a developer needs it, and it
  changes nothing in release.

## Scope

- Includes:
  - `lib/core/services/error_report_store.dart`: the store (record, read,
    clear, the cap and the queued writes) and `installErrorReporting`.
  - A provider for the store in `lib/providers/`.
  - `lib/main.dart`: installing the hooks before `runApp`.
  - `lib/core/features/settings/settings_screen.dart`: the share row, and the
    report cleared by "Apagar todos os dados". The pt-BR strings go to
    `app_strings.dart`.
  - Tests: `test/services/error_report_store_test.dart` and the settings screen
    tests.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): the services and
    providers lines.
- Does NOT include:
  - Any remote sink, or any automatic transmission.
  - Native crashes and ANRs, which Android vitals reports.
  - Failures inside the inference isolate, which already return as named causes
    (ADR 0015) rather than as uncaught errors.
  - Writing the Data safety answers or the privacy policy (#293, #276).

## Acceptance Criteria

- `an_uncaught_error_is_recorded_with_its_type_and_stack`: an error passed to
  the installed `FlutterError.onError`, and one passed to
  `PlatformDispatcher.instance.onError`, each add an entry with its source,
  runtime type and stack trace.
- `the_report_redacts_coordinates_tokens_and_emails`: an error whose message
  holds a coordinate pair in both the six-place and the raw `double` form, a
  `ya29.` token, a JWT and an email leaves none of them in the file, and the
  rest of the message is kept.
- `a_long_message_is_cut_to_300_characters`: a 1,000-character message is
  written as its first 300 characters after redaction.
- `the_report_keeps_the_newest_fifty_entries`: after 51 records the file holds
  50, and the oldest is the one dropped.
- `a_failed_write_never_throws_from_the_handler`: with storage that throws, the
  handlers return normally.
- `the_previous_framework_handler_still_runs`: the handler `FlutterError.onError`
  held before installation is called with the same details.
- `settings_shares_the_error_report`: with entries, the row shares the file;
  without entries, it is disabled.
- `erasing_all_data_clears_the_error_report`: confirming "Apagar todos os
  dados" leaves the report empty.
- `flutter analyze`, the full suite and `mf check` pass.

## Reproducibility

```sh
flutter test test/services/error_report_store_test.dart \
  test/features/settings/settings_screen_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Risk: an address survives redaction.** #287's criterion asks that no
  report contain a coordinate, an address or a token. This design meets the
  coordinate and token parts. For the address part, the Developer accepted the
  residual risk at the Gate, as described above. The privacy policy (#276) says
  that a shared report may contain fragments of what failed.
- **Risk: redaction removes a useful number.** A probability or measurement
  printed with three or more decimals becomes `<number>`. The message still
  names the failure, and the stack still locates it.
- **Assumption: stack frames hold no user data.** Dart frames are code
  locations (`package:` URIs, line and column). Release builds are not
  obfuscated today. If obfuscation is enabled later, frames need the symbol
  map to read, and still hold no data.
- **Risk: a user never shares.** Then the maintainer learns nothing, which is
  the trade the Developer chose. The closed test (#297) is where testers are
  asked to send it.
