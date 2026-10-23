# Physics cost comparison for #16

Reference: `2517ebf2cfb9f04cca14c505d886fe332132a1ac`. Candidate: this PR.
Measured 2026-10-23 on the macOS arm64 host, Release, both cores reporting
10,000 Hz at 3000 RPM. One 0.5 s settling render and one discarded 3 s warm-up,
then five timed 3 s renders per profile. Each revision ran sequentially after local
Simulator tests and package builds completed. These are host diagnostics,
not physical iPhone acceptance evidence.

| Profile | Reference min/median/max | Candidate min/median/max | Median reduction |
| --- | --- | --- | --- |
| LS V8 | 0.488855 / 0.491048 / 0.493528 | 0.447203 / 0.449157 / 0.453045 | 8.5% |
| F136 V8 | 0.486540 / 0.491862 / 0.517622 | 0.444644 / 0.447314 / 0.449765 | 9.1% |

An earlier pass gave LS median 0.502508 → 0.447006 and F136
0.498302 → 0.444590. O3 + ThinLTO alone was neutral; defining NDEBUG
accounts for most of the measurable improvement. A follow-up O2/NDEBUG-only
probe measured medians 0.463429 (LS) and 0.451736 (F136), compared with the
combined candidate’s 0.449157/0.447314; the combined flags are retained.
No physics formulas, iteration limits,
fluid substeps, or defaults changed.

## Render comparison

The root accepted tolerance: RMS ±1%, firing peak within 3% of RPM/15,
dominant 40–600 Hz peak within one FFT bin (0.673 Hz), no silence/clipping.
Both profiles at 1500/3000/5000 RPM and throttle 0/0.5/1 passed. Each capture
contains exactly 88,200 frames; peak sample magnitude ranges 6232–25656.
The reference and candidate firing and dominant frequency bins match in all
18 cases. Maximum absolute RMS change is 0.310%.

| Profile | RPM | Throttle | Firing Hz | Dominant Hz | RMS change | Candidate peak |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| LS | 1500 | 0 | 100.264 | 437.393 | +0.000% | 20637 |
| LS | 1500 | 0.5 | 100.264 | 62.581 | +0.130% | 20516 |
| LS | 1500 | 1 | 100.264 | 62.581 | +0.310% | 20729 |
| LS | 3000 | 0 | 199.855 | 399.710 | +0.000% | 19626 |
| LS | 3000 | 0.5 | 199.855 | 199.855 | +0.000% | 24988 |
| LS | 3000 | 1 | 199.855 | 199.855 | -0.205% | 25656 |
| LS | 5000 | 0 | 333.092 | 458.253 | +0.000% | 21252 |
| LS | 5000 | 0.5 | 333.092 | 458.253 | +0.000% | 20596 |
| LS | 5000 | 1 | 333.092 | 125.162 | -0.126% | 22080 |
| F136 | 1500 | 0 | 100.264 | 199.855 | +0.003% | 19950 |
| F136 | 1500 | 0.5 | 100.264 | 100.264 | -0.005% | 6232 |
| F136 | 1500 | 1 | 100.264 | 100.264 | +0.011% | 6277 |
| F136 | 3000 | 0 | 199.855 | 199.855 | -0.006% | 20905 |
| F136 | 3000 | 0.5 | 199.855 | 100.264 | +0.011% | 17862 |
| F136 | 3000 | 1 | 199.855 | 100.264 | +0.011% | 17830 |
| F136 | 5000 | 0 | 333.092 | 333.092 | -0.002% | 20329 |
| F136 | 5000 | 0.5 | 333.092 | 166.882 | +0.011% | 19635 |
| F136 | 5000 | 1 | 333.092 | 166.882 | -0.023% | 19208 |

## Verification

- Full Release host suite: 44 tests, 20 platform/opt-in skips, 0 failures.
- Release guard probe: NaN, +Inf and -Inf injected into chamber energy, friction
  coefficient and solver velocity leave force accumulators unchanged. Finite
  pressure still applies force. Removing both guards makes the probe fail with
  `Invalid chamber force reached the solver` (exit 1).
- Full Release iPhone 17 Pro / iOS 26.5 Simulator suite: 46 tests, 1 opt-in
  benchmark skip, 0 failures. `ENABLE_TESTABILITY=YES` enables the package test
  targets’ `@testable` imports under Release.
- `git diff --check` passes.

## Physical measurement pending

The paired iPhone 12 Pro is available, but the checked-in benchmark project has
no development team; a signed device build currently fails with “requires a
development team”. Owner must select the team locally in Xcode or provide its
identifier as a build setting. No credentials or signing configuration are
checked in. Run the cool and warm reference/candidate procedure in
[`swift/README.md`](../../README.md#physics-performance-comparison-16), and
record actual thermal states and LS/F136 min/median/max before calling #16 done.
The existing #6 strict `<0.7` gate stays unchanged. #16's proposed cool `≤0.5`
and warm `<0.7` targets await owner confirmation and physical results.
