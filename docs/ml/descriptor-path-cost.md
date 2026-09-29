# The descriptor path's cost per photograph

The measurement [SPEC 0086](../specs/0086-measure-the-descriptor-path-cost-per-photograph.md)
specifies, and item A7 of the implementation map asks for. It covers what one
classification costs on an Android emulator, phase by phase, against the 15 s
timeout `InferenceService.classify` enforces. It is engineering feedback on the
adopted path (ADR 0024), not a gate.

## The answer

**One classification fits inside 15 s on the emulator, with a margin of about
2.5×. The cost is the JPEG decode, not the descriptors.**

| Phase | Median (ms) | Max (ms) |
|---|---:|---:|
| Decode (`img.decodeImage`) | 3 537 | 3 741 |
| Orientation bake | 21 | 58 |
| Frame conversion | 60 | 95 |
| Grid: resample to the canonical scale and cut | 182 | 224 |
| Describe: 26 descriptors for each of 25 patches | 564 | 619 |
| Score (`DescriptorContract.distribution`) | 0 | 0 |
| **`classify`, end to end** | **5 505** | **6 109** |

Five runs of each. Every `classify` run returned an `ok` report.

- **The decode is about 80 % of the phases' time.** That is 3.5 s of the
  4.4 s the phases add up to.
- **The descriptors cost about 23 ms a patch.** That is roughly half of the
  desktop JIT's 40 ms (SPEC 0077). AOT compilation is the likely reason, though
  it is not isolated here. The 25 patches together are about 0.6 s.
- **`classify` adds about 1.1 s over the sum of the phases.** It reads the file
  again, spawns the isolate and copies the contract into it. The phases above
  ran on the test's own thread.

## What was measured

| | |
|---|---|
| Photograph | 3024 × 4032 px (12 MP, portrait), uniform noise, JPEG quality 90, 22.8 MB |
| Scale | 90 mm over 2 700 px, a centred disc: 0.0333 mm/px |
| Patches cut | 25 |
| Contract | `assets/models/spec.json`, release `1.0.0` |
| Mode | profile (AOT), through `flutter drive --profile` |
| Device | AVD `android_emulator`: x86_64, API 36, 4 cores, 4 GB RAM |
| Host | Intel Core i5-1135G7, 4 cores / 8 threads, 20 GB RAM, Windows 11, hypervisor acceleration |
| Flutter | 3.44.1 (Dart 3.12.1) |
| Date | 2026-09-29 |

**The photograph is the decoder's worst case.** Noise does not compress, so the
entropy-coded data a decoder must read is as large as it can be at this size.
A camera JPEG of the same 12 MP pays the same per-pixel work but reads less
coded data, so it decodes no slower. The archive has no 12 MP JPEG to compare
against: its 12 MP population is PNG converted from HEIC (#196).

**The scale stands in for the A4-sheet reader,** which does not exist. What the
reader costs is not in these numbers.

## How to read it

**The margin belongs to this emulator, not to a phone.** A7 records why a
number from an x86_64 emulator on a desktop CPU does not transfer to an ARM
phone in either direction. This emulator runs AOT x86_64 code at close to the
host's speed, with no thermal ceiling. On the worst-case photograph, a phone
about 2.5× slower than this emulator would reach the 15 s timeout. Whether
mid-range phones are that much slower is not measured here, and no physical
device is available (A7, revised 2026-09-05).

**Resolution scales the decode.** Capture keeps the camera's full resolution:
`pickImage` is called with no `maxWidth`. So 12 MP is the common case. A phone
that writes full-resolution 48 or 50 MP photographs would decode about four
times the pixels, which is not measured here.

**What the numbers do not decide.** Neither an optimisation nor a longer timeout
follows from this record alone. If one is wanted, the decode is where it would
pay, and the descriptors are not. Examples are decoding at reduced size, since
the grid resamples to 0.129 mm/px anyway, or a platform decoder. That decision
belongs to its own spec, against a device measurement if one becomes possible.

## Reproducing it

Boot the AVD, then run from the repository root:

```sh
flutter drive --profile -d emulator-5554 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/descriptor_path_cost_test.dart
```

The timings are written to `build/integration_response_data.json`. The first
profile build takes a few minutes; this run took 5 min 50 s wall time,
including the build.
