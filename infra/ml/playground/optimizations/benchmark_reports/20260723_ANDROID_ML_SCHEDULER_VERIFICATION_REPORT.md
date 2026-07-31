# Android ML scheduler verification report

Date: 2026-07-23 (Asia/Kolkata)  
Branch: `ort_opt_ios`, HEAD `3c9ee2cb76` plus the re-applied benchmark
instrumentation and the scheduler-verification additions described below.  
Device: Google Pixel 8 (`shiba`), Android 17, ONNX Runtime WebGPU.  
Baseline for comparison: `20260722_FINAL_MOBILE_ML_BENCHMARK_REPORT.md`.

## Executive summary

The 2026-07-22 benchmark showed iPhone 15 Pro beating Pixel 8 by ~12x on
Rust pre-processing and ~4x on serial decode, far beyond the ~1.6-2x silicon
gap between the two SoCs. This follow-up ran four instrumented variants on
the same Pixel 8 to find out why. The verdict:

**The Pixel's CPU-side slowness is caused by DVFS and scheduling, not by
hardware and not primarily by the rayon fan-out.** The ML pipeline's short
CPU bursts (each following a ~240 ms GPU-inference sleep, rotated across ~9
worker threads) never accumulate enough per-thread utilization for Android's
scheduler to raise clocks or migrate to fast cores. Baseline pre-processing
ran mostly on mid cores at a **median of 910 MHz** (38% of their 2.37 GHz
max). Concentrating all pipeline work on one big core (variant D) raised the
sustained clock to **2,363 MHz** and collapsed corpus pre-processing from
**596.7 ms to 212.4 ms (2.8x)** — into the range the silicon is expected to
deliver — and produced the fastest end-to-end run of all variants despite
using one core instead of nine.

| Corpus totals, 13 common fixtures (ms) | A: baseline | B: serial rayon | C: no little cores | D: serial + 1 big core |
|---|---:|---:|---:|---:|
| decode | 2,772.1 | 3,907.5 | 2,898.9 | 3,194.0 |
| **Rust pre-processing** | **596.7** | **535.9** | **472.2** | **212.4** |
| inference (WebGPU) | 3,349.5 | 3,947.7 | 3,622.8 | 3,159.8 |
| Rust post-processing | 13.6 | 8.5 | 11.4 | 9.6 |
| Rust other | 103.0 | 119.0 | 105.4 | 62.7 |
| Rust total | 6,874.5 | 8,536.2 | 7,073.9 | **6,652.6** |

## Variants and validity

All variants: AOT release (`connectedIndependentReleaseAndroidTest`,
`dart.vm.product=true` verified per run — via results payload for A/C/D and
via the passing `ML_PARITY_REQUIRE_RELEASE=true` gate for B), 14-fixture
corpus, 1 unmeasured warm-up + 3 measured samples per fixture, per-file
medians. Device thermal status was 1 (light) before and after every variant
(the 07-22 run reported 0), constant across variants, so cross-variant
comparisons are internally consistent. Corpus sums above use the 13 fixtures
successful in every variant.

| Variant | Compile-time override | `bench_config` confirmation |
|---|---|---|
| A | none (baseline + placement sampling) | rayon pool 9 threads, no affinity |
| B | `ENTE_ML_BENCHMARK_RAYON_THREADS=1` | pool configured to 1 thread |
| C | `ENTE_ML_BENCHMARK_CPU_AFFINITY=4-8` | mask `0x1f0`, 9/9 workers pinned |
| D | both, affinity `8` (Cortex-X3 only) | pool 1 thread, all work on cpu8 |

New instrumentation (compiled out of production builds): per-stage
`sched_getcpu()` + DVFS frequency sampling outside the stage clocks, and a
rayon wake-latency probe (empty `broadcast` timed after each pipeline).

## Where the stages actually ran

Cluster topology: cpu0-3 Cortex-A510 ("little", 1.70 GHz max), cpu4-7
Cortex-A715 ("mid", 2.37 GHz max), cpu8 Cortex-X3 ("big", 2.91 GHz max).

| Stage (variant A baseline) | Placement (share of stage time) | Median frequency |
|---|---|---|
| decode (long bursts) | 42% mid / 58% big | mid 1,418 MHz, big 2,687 MHz |
| pre-processing (short bursts) | 3% little / 61% mid / 37% big | mid **910 MHz**, big 1,557 MHz |
| post-processing (µs bursts) | 98% mid | **697 MHz** |

The pattern predicted by the 07-22 analysis is measured directly: only long
decode bursts earn high clocks mid-burst; short pre/post bursts start and
finish cold. In variant D the same pre-processing ran at 2,363 MHz and its
per-invocation median fell from 15.0 ms to **5.4 ms** (p90 30 ms → 10 ms,
max 81 ms → 21 ms).

Rayon wake probe (fan-out barrier tax per resize dispatch): median 2.2 ms,
p90 4.9 ms in A, with 46% of pool workers waking on little cores; still
2.4 ms median in C with all workers pinned to mid+big (the tax is idle-exit
latency, not little-core placement); 0.10 ms with a single-thread pool (D).

## Hypothesis outcomes

- **H1 — rayon fan-out barrier dominates pre-processing: REFUTED as the
  dominant cost, confirmed as a real secondary cost.** Serializing the pool
  (B) recovered only ~60 ms of the ~597 ms corpus pre-processing (~10%),
  bimodally: small fixtures collapsed (1343.jpg 39.6 → 13.0 ms — pure
  barrier tax), while large or face-heavy fixtures got worse (pano 39.7 →
  59.3 ms, people.jpeg 74.2 → 84.8 ms) because real parallel compute was
  lost. The ~2-5 ms/dispatch barrier tax is real but bounded.
- **H2 — cold-core/DVFS placement dominates: CONFIRMED, with frequency as
  the decisive lever.** Excluding little cores (C) improved pre-processing
  only 21% because mid cores still idled at 910 MHz. Concentrating work on
  one core (D) let schedutil sustain 2,363 MHz and delivered 2.8x. Placement
  alone is not the fix; sustained utilization is.
- **Decode parallelism is worth keeping.** Serial decode (B) cost +1,135 ms
  corpus-wide, almost entirely on two large/tiled HEICs (pano 714 → 1,426 ms,
  8606 239 → 519 ms); ordinary HEICs decode near-serially anyway. On the
  ramped core (D), the serial JPEG/PNG/WebP decoders got *faster* than
  baseline (astronaut.png 11.6 → 5.0 ms, ui_app.webp 121.5 → 79.9 ms).
- **Reconciliation with iPhone.** On the 13 common fixtures the iPhone 15
  Pro's pre-processing total is ~51 ms. Variant D brings the Pixel from
  11.7x behind to ~4.2x; the residual is the genuine silicon gap (~2-3x
  single-core) plus the X3 sitting at 2,363 rather than 2,914 MHz between
  inference sleeps. The original "~10x slower at everything" reading of the
  07-22 report is disproved: it was measuring scheduler behavior.

## Anomalies and caveats

- `IMG_8905.CR2` failed its platform JPEG fallback in C and D (succeeded in
  A, B, and all 07-22 runs). Both failures occurred after the harness began
  leaving the app installed between variants (persistent app data), which is
  currently the leading suspect rather than the affinity override itself.
  Needs a targeted re-run before any affinity-related change ships. The
  common-file analysis excludes this fixture, so headline numbers are
  unaffected.
- WebGPU inference varied ±9% across variants (3,160-3,948 ms) with no
  clear ordering; treat inference deltas between variants as noise.
- Thermal status was 1 throughout (07-22: 0). Baseline A nonetheless
  reproduced the 07-22 corpus totals (decode 2,772 vs 2,771 ms; pre 597 vs
  653 ms), so the instrumentation and thermal state did not distort the
  benchmark.
- A/B logcat captures each lost one fixture's events to ring-buffer
  eviction before the buffer was enlarged to 16 MB; handled by the
  common-file analysis.
- Variant D's hard pin is a diagnostic, not a shippable configuration: it
  monopolizes the X3, ignores thermal headroom, and fights other workloads.

## Recommendations

Ranked by expected value for production Android indexing:

1. **Stop rotating pipeline work across the FRB worker pool; run the ML
   pipeline on one persistent dedicated thread** (optionally a second for
   decode). This is the shippable form of what variant D measured: thread
   concentration is what lets schedutil sustain high clocks. No pinning
   required as a first step.
2. **Pipeline CPU and GPU**: decode/pre-process image N+1 while image N is
   inside `Session::run`. This both hides pre-processing latency entirely
   and keeps the worker thread's utilization high so clocks stay up —
   attacking decode's 2-4x deficit too, which per-stage fixes cannot.
3. **Adopt ADPF (`PerformanceHintManager`)** for the ML worker thread(s)
   with the per-image target duration; this is the sanctioned mechanism for
   exactly this bursty-workload/DVFS problem and replaces any affinity hack.
4. **Drop the `rayon` feature from `fast_image_resize` in
   `rust/crates/photos`** (keep `heic_decoder`'s own rayon parallelism for
   decode). The resize fan-out never pays for itself — B was net *faster*
   on pre-processing without it — and it stops paying the 2-5 ms barrier
   per dispatch. Small, safe, immediate.
5. **Do not ship CPU affinity pinning** without resolving the CR2 anomaly
   and testing under contention/thermal load; revisit only if 1-3
   underdeliver.
6. **Correct the 07-22 report's cross-platform framing**: the CoreML-vs-
   WebGPU inference gap (5.7-8.8x) is a genuine platform gap, but the
   pre/post/decode gaps are ~1.6-2x silicon plus Android scheduling debt
   that items 1-4 reclaim.

Estimated steady-state impact of items 1+2+4 combined, before any inference
work: roughly 10-20% end-to-end on this corpus (pre-processing 597 → ~210
ms, "other" 103 → ~60 ms, serial-decoder fixtures 1.5-2x faster, large-HEIC
decode unchanged), with the larger strategic value being that CPU cost stops
scaling with scheduler mood and the WebGPU inference gap becomes the single
remaining Android deficit.

## Artifacts

Per-variant logs, thermal snapshots, and result payloads:

- `infra/ml/test/out/sched_verification_2026-07-23/{A,B,C,D}/device_logcat.txt`
- `infra/ml/test/out/sched_verification_2026-07-23/{A,C,D}/results.json`
  (B's payload was lost to the harness's post-test auto-uninstall; its
  benchmark data is complete in the logcat)
- Analyzer: `python3 infra/ml/test/tools/analyze_ml_sched_verification.py
  <device_logcat.txt>` (placement, frequencies, probe, corpus totals)
- Procedure: `20260723_ANDROID_SCHED_VERIFICATION_RUNBOOK.md`
