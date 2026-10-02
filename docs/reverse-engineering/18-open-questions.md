# 18 — Open questions

| # | Question | Why it matters | How it could be answered legitimately |
|---|---|---|---|
| Q1 | What prompt and JSON schema does the identification call send and expect? | defines the result contract | not answerable without decompiling the bytecode, which was out of scope; the field list in [05](05-domain-model.md) is the observable shadow |
| Q2 | What happens with a real soil photo: confidence, texture vocabulary, number of candidates? | the non-soil run only showed the defaults | run one identification on a real soil photo with a premium or fresh install (costs a scan) |
| Q3 | Does chat write refined fields back to the record (`applySoilUpdates`)? | data integrity | chat with a working model about a real soil, then compare the details screen |
| Q4 | Why did the first chat turn fail online? | model availability vs refusal | retry later; a stable failure would indicate a configuration or quota issue on their side |
| Q5 | Is there a premium scan cap (`PREMIUM_SCANS`)? | quota rules | only observable with an active subscription; not pursued |
| Q6 | Are photos copied out of the cache directory for long-term storage? | records could lose their images | observe after clearing the app cache (Android settings), without clearing data |
| Q7 | Is the store review dialog actually requested on the social proof screen? | funnel | Play only shows the dialog in some conditions; inspect a test-track build of our own instead |
| Q8 | What do Remote Config and PostHog flags change at run time (paywall variants, survey timing)? | experimentation | not observable from one device; out of scope |
| Q9 | Is location ever attached to a record? | parity with VisioSoil's GPS capture | look for a location prompt on the "+" path or in the gallery import |
| Q10 | What triggers `SurveyModal`? | engagement | use the app over several days; PostHog survey targeting is server-side |
| Q11 | What does the Delete All Data confirmation look like, and does it log RevenueCat out? | data rights | exercise it on a disposable install |
| Q12 | Does an online relaunch after onboarding re-show the paywall? | conversion rules | relaunch online after force-stop |

## Session notes

- The analysis used the install's single free scan, so Q2 needs a fresh install.
- `uiautomator dump` does not see the paywall modal; use screenshots for that screen. Taps near the paywall's CTA start the Play billing flow, so drive that screen by screenshot only.
