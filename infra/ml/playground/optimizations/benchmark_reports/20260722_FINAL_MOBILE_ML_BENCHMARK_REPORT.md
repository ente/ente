# Final mobile ML indexing benchmark

Date: 2026-07-22 (Asia/Kolkata)  
Branch: `ort_opt_ios`  
HEAD: `b7b5df29eb` (plus the benchmark instrumentation described below)

## Executive summary

- Both physical devices completed all 14 fixtures in AOT release mode with zero result-generation errors.
- The iOS persistent CoreML cache is highly effective. Total load time for the three models fell from **8,595.5 ms with caching disabled** to **840.8 ms with a warm persistent cache**: a **90.2% reduction / 10.2x speed-up**.
- The cache-on priming run was correctly reported as cold for all models and took 4,306.4 ms. The next launch reported all three models as warm and took 840.8 ms.
- Median end-to-end steady-state indexing time for all 14 fixtures was **12,994.3 ms on Pixel 8 (928.2 ms/image)** and **5,022.2 ms on iPhone 15 Pro (358.7 ms/image)**. The iPhone was 2.59x faster end to end and 4.06x faster inside the Rust pipeline.
- Mobile-to-mobile correctness passed **14/14** for Android versus every iOS cache variant. Against the Python ground truth, all variants passed **13/14**. The only mismatch was the already-understood `IMG_8905.CR2` CLIP embedding difference: mobile uses the platform-generated JPEG fallback after direct RAW decode fails, whereas Python indexes its different RAW decode.
- Rust post-processing is now negligible in the corpus totals: 12.7 ms on Pixel and 2.3 ms on iPhone. On Pixel, inference and decode dominate the measured Rust time. On iPhone, decode dominates Rust time; end-to-end time is dominated by the CR2 platform fallback outside Rust.

## Devices and release evidence

| Device | OS | Execution provider | Release evidence |
|---|---|---|---|
| Google Pixel 8 (`shiba`) | Android 17, API 37, build `CP2A.260705.006` | ONNX Runtime WebGPU | `dart.vm.product=true`, `dart.vm.profile=false`; APK `debuggable=false`; Android instrumentation `OK (1 test)` |
| iPhone 15 Pro (`iPhone16,1`, D83AP) | iOS 26.5.2, build `23F84` | ONNX Runtime CoreML | `flutter build ios --release`; `dart.vm.product=true`, `dart.vm.profile=false` in every result payload |

The Pixel reported device thermal status 0 before and after the final run. Current CPU/GPU sensors and cooling devices also reported no CPU/GPU throttling. iOS does not expose a comparable thermal status through the device-control interface used here; no thermal warnings were emitted.

## Method

- Corpus: the existing 14-image ML parity manifest.
- Each fixture received one unmeasured warm-up followed by three measured samples. Per-file values below are medians; corpus totals are the median of three full-corpus sums.
- Fixture/model staging and downloads happened before timing. Lazy model loading happened during warm-up and was measured separately.
- `Dart total` is the user-visible call duration and is the requested total indexing time. It includes FFI/platform work such as the CR2 JPEG fallback.
- `Rust total` covers the successful Rust pipeline only. It is split into decode, Rust pre-processing, exact ONNX `Session::run`, Rust post-processing, and small unclassified Rust overhead.
- Model-load timing includes session construction plus the accelerated-provider zero-input and golden self-tests, matching the cost seen by application initialization.
- CoreML configurations were compiled separately with `ENABLE_PERSISTENT_COREML_CACHE` absent (off) and present (on). The cache-on binary was run once to prime its application-container cache and then relaunched without reinstalling for the warm measurement.

## Model load

Only the three image-indexing models exercised by this corpus were loaded.

| Device / cache state | YOLO face detector | MobileCLIP image | MobileFaceNet | Total |
|---|---:|---:|---:|---:|
| Pixel 8 WebGPU | 1,311.6 ms | 1,196.6 ms | 351.0 ms | **2,859.2 ms** |
| iPhone CoreML, cache off | 1,774.0 ms | 5,664.8 ms | 1,156.7 ms | **8,595.5 ms** |
| iPhone CoreML, cache on, cold prime | 432.7 ms | 3,656.9 ms | 216.8 ms | **4,306.4 ms** |
| iPhone CoreML, cache on, warm | 153.4 ms | 638.1 ms | 49.2 ms | **840.8 ms** |

Warm-cache reductions versus cache off:

| Model | Time saved | Reduction | Speed-up |
|---|---:|---:|---:|
| YOLO face detector | 1,620.5 ms | 91.4% | 11.6x |
| MobileCLIP image | 5,026.7 ms | 88.7% | 8.88x |
| MobileFaceNet | 1,107.4 ms | 95.7% | 23.5x |
| **Total** | **7,754.7 ms** | **90.2%** | **10.2x** |

The cold cache-on prime was already 49.9% faster than cache-off, but the robust user-facing comparison is cache-off versus the explicitly verified warm state. MobileCLIP remains the largest warm-start contributor at 638.1 ms (75.9% of total load time).

## Corpus totals

Model load is excluded from these steady-state totals.

| Run | End-to-end 14 images | End-to-end / image | Rust total | Rust / image |
|---|---:|---:|---:|---:|
| Pixel 8 WebGPU | **12,994.3 ms** | **928.2 ms** | 7,265.3 ms | 518.9 ms |
| iPhone CoreML, cache off | **4,998.0 ms** | **357.0 ms** | 1,796.2 ms | 128.3 ms |
| iPhone CoreML, cache on, cold prime | **4,976.9 ms** | **355.5 ms** | 1,773.6 ms | 126.7 ms |
| iPhone CoreML, cache on, warm | **5,022.2 ms** | **358.7 ms** | 1,789.8 ms | 127.8 ms |

The three iPhone steady-state totals are within 0.9%, confirming that persistent caching changes model startup, not inference output or steady-state throughput.

### Stage totals and end-to-end shares

| Device | Decode | Rust pre | Inference | Rust post | Rust other | Outside Rust / platform |
|---|---:|---:|---:|---:|---:|---:|
| Pixel 8 | 2,771.0 ms (21.3%) | 652.8 ms (5.0%) | 3,720.0 ms (28.6%) | 12.7 ms (0.10%) | 117.2 ms (0.9%) | 5,729.0 ms (44.0%) |
| iPhone 15 Pro, warm | 1,169.6 ms (23.3%) | 55.1 ms (1.1%) | 557.9 ms (11.1%) | 2.3 ms (0.05%) | 0.5 ms (0.01%) | 3,232.4 ms (64.4%) |

Almost all `Outside Rust / platform` time comes from `IMG_8905.CR2`: the direct Rust RAW decode fails quickly, then Dart/platform code renders a JPEG fallback before retrying Rust indexing. Excluding CR2, the summed per-file medians are approximately 6.99 s for the other 13 Pixel fixtures (537.6 ms/image) and 1.66 s on iPhone (128.0 ms/image).

## Per-file timings: Pixel 8 WebGPU

All values are milliseconds. `Outside Rust` is `Dart total - Rust total`.

| Fixture | Dart total | Decode | Rust pre | Inference | Rust post | Rust total | Outside Rust |
|---|---:|---:|---:|---:|---:|---:|---:|
| `1343_rotate_90_cw.jpg` | 457.3 | 157.2 | 45.3 | 236.8 | 1.1 | 449.4 | 7.9 |
| `1718_rotate_90_cw.HEIC` | 844.6 | 514.4 | 50.3 | 252.4 | 0.5 | 832.6 | 12.0 |
| `7765_horizontal_normal.HEIC` | 894.1 | 565.6 | 56.8 | 248.5 | 0.7 | 881.6 | 12.5 |
| `7949_mirror_horizontal_rotate_270_cw.HEIC` | 453.4 | 144.2 | 37.9 | 251.1 | 1.0 | 443.0 | 10.4 |
| `IMG_0682_pano.HEIC` | 974.5 | 647.8 | 37.8 | 247.6 | 0.6 | 963.0 | 11.5 |
| `IMG_8606_rotate_90_cw_contains_text.HEIC` | 556.3 | 253.0 | 40.6 | 237.2 | 0.5 | 546.1 | 10.2 |
| `IMG_8905.CR2` | 6,005.9 | 205.9 | 48.0 | 237.8 | 0.3 | 503.0 | 5,502.9 |
| `IMG_pano.jpg` | 467.1 | 157.3 | 39.2 | 253.9 | 1.0 | 459.0 | 8.1 |
| `astronaut.png` | 316.9 | 10.5 | 35.7 | 251.7 | 1.8 | 307.2 | 9.7 |
| `man.jpeg` | 302.0 | 1.2 | 32.3 | 252.8 | 1.2 | 288.6 | 13.4 |
| `people.jpeg` | 443.4 | 1.5 | 73.4 | 355.4 | 1.6 | 425.2 | 18.2 |
| `singapore.jpg` | 335.5 | 49.2 | 32.2 | 242.3 | 1.5 | 328.0 | 7.5 |
| `starwatchers.jpg` | 335.2 | 22.9 | 39.6 | 254.8 | 1.7 | 317.6 | 17.6 |
| `ui_app.webp` | 606.6 | 92.0 | 79.3 | 405.7 | 1.1 | 585.9 | 20.7 |

## Per-file timings: iPhone 15 Pro CoreML, warm cache

All values are milliseconds.

| Fixture | Dart total | Decode | Rust pre | Inference | Rust post | Rust total | Outside Rust |
|---|---:|---:|---:|---:|---:|---:|---:|
| `1343_rotate_90_cw.jpg` | 77.1 | 39.5 | 3.7 | 33.2 | 0.1 | 76.4 | 0.7 |
| `1718_rotate_90_cw.HEIC` | 323.1 | 274.6 | 4.5 | 43.1 | 0.1 | 322.3 | 0.8 |
| `7765_horizontal_normal.HEIC` | 375.2 | 327.3 | 5.5 | 41.7 | 0.1 | 374.4 | 0.8 |
| `7949_mirror_horizontal_rotate_270_cw.HEIC` | 91.7 | 49.0 | 2.8 | 39.0 | 0.1 | 91.0 | 0.7 |
| `IMG_0682_pano.HEIC` | 275.6 | 229.6 | 5.9 | 40.2 | 0.1 | 274.8 | 0.8 |
| `IMG_8606_rotate_90_cw_contains_text.HEIC` | 108.4 | 62.3 | 4.9 | 40.2 | 0.1 | 107.7 | 0.7 |
| `IMG_8905.CR2` | 3,358.2 | 77.4 | 6.3 | 40.7 | 0.1 | 124.0 | 3,234.2 |
| `IMG_pano.jpg` | 108.7 | 63.4 | 2.0 | 42.3 | 0.1 | 107.9 | 0.8 |
| `astronaut.png` | 40.7 | 2.5 | 2.6 | 34.7 | 0.2 | 40.0 | 0.7 |
| `man.jpeg` | 39.2 | 0.3 | 2.4 | 35.2 | 0.2 | 38.1 | 1.1 |
| `people.jpeg` | 58.1 | 0.5 | 5.6 | 49.0 | 0.3 | 55.6 | 2.5 |
| `singapore.jpg` | 48.7 | 11.6 | 2.4 | 33.5 | 0.2 | 47.8 | 0.9 |
| `starwatchers.jpg` | 43.3 | 4.8 | 2.4 | 34.9 | 0.2 | 42.3 | 1.0 |
| `ui_app.webp` | 78.9 | 24.0 | 4.6 | 48.6 | 0.1 | 77.6 | 1.3 |

## Exact model inference

These are medians of the timed ONNX `Session::run` call, excluding tensor construction and output extraction. Counts reflect three measured corpus passes: 42 detector and CLIP calls, and 75 face-embedding calls.

| Model | Pixel 8 WebGPU | iPhone CoreML, warm | iPhone speed-up |
|---|---:|---:|---:|
| YOLO face detection | 108.03 ms | 19.03 ms | 5.68x |
| MobileCLIP image | 129.23 ms | 18.38 ms | 7.03x |
| MobileFaceNet embedding | 15.31 ms | 1.75 ms | 8.75x |

Images with more detected faces naturally have more inference time. For example, `people.jpeg` has seven face-embedding calls per pass and `ui_app.webp` has ten.

## Correctness smoke test

| Comparison | Passing | Warning | Failing |
|---|---:|---:|---:|
| Python -> Pixel 8 | 13 | 0 | 1 (`IMG_8905.CR2`) |
| Python -> iPhone cache off | 13 | 0 | 1 (`IMG_8905.CR2`) |
| Python -> iPhone cache on, cold | 13 | 0 | 1 (`IMG_8905.CR2`) |
| Python -> iPhone cache on, warm | 13 | 0 | 1 (`IMG_8905.CR2`) |
| Pixel 8 -> iPhone cache off | **14** | 0 | 0 |
| Pixel 8 -> iPhone cache on, cold | **14** | 0 | 0 |
| Pixel 8 -> iPhone cache on, warm | **14** | 0 | 0 |

For the one Python mismatch, the mobile/Python CR2 CLIP cosine distance is about 0.196 against a 0.015 threshold. Android and iOS agree on that same fallback input: their maximum CLIP cosine distance across all 14 files is `9.83e-12`. Their face boxes match exactly, and maximum mobile-to-mobile face-embedding cosine distance is `5.76e-7`.

The four direct Rust decode failures in each run are expected: one warm-up plus three measured direct attempts for the CR2 fixture. Each is followed by a successful JPEG fallback pipeline. The final result documents contain 14 results and zero errors.

## Interpretation and recommendation

1. **Enable the persistent CoreML cache.** A verified warm launch saves 7.75 seconds across these three production image-indexing models, while correctness and steady-state performance remain unchanged.
2. **Treat RAW fallback conversion as a separate optimization target.** It accounts for about 5.50 seconds on Pixel and 3.23 seconds on iPhone for this single CR2. It is now far larger than the successful Rust indexing pass (503 ms and 124 ms respectively).
3. **Decode and inference are the remaining normal-image costs.** On Pixel, WebGPU inference is the largest measured Rust component; on iPhone, HEIC/JPEG decode is larger than CoreML inference. Rust post-processing is no longer a meaningful bottleneck.
4. **The correctness signal is clean apart from the known input mismatch.** For a fully green Python gate, either make the Python CR2 ground truth consume the same rendered JPEG fallback or maintain a separate RAW-decoder golden. The production mobile implementations already agree 14/14.

## Benchmark instrumentation and artifacts

Benchmark logging is compile-time opt-in through `ENTE_ML_BENCHMARK_LOGGING`; normal builds do not emit these timings. The Android release-instrumentation support is also opt-in through `ENTE_ML_BENCHMARK_RELEASE_TESTS=1`. Normal release signing and dependencies remain unchanged when the switch is absent.

Machine-readable artifacts:

- [Pixel summary](../../../test/out/final_mobile_ml_benchmark_2026-07-22/android/benchmark_summary.json), [result payload](../../../test/out/final_mobile_ml_benchmark_2026-07-22/android/results.json), and [device log](../../../test/out/final_mobile_ml_benchmark_2026-07-22/android/device_logcat.txt)
- [iPhone cache-off summary](../../../test/out/final_mobile_ml_benchmark_2026-07-22/ios_cache_off/benchmark_summary.json)
- [iPhone cold-prime summary](../../../test/out/final_mobile_ml_benchmark_2026-07-22/ios_cache_on_prime/benchmark_summary.json)
- [iPhone warm-cache summary](../../../test/out/final_mobile_ml_benchmark_2026-07-22/ios_cache_on_warm/benchmark_summary.json)
- [Python-ground-truth comparison](../../../test/out/final_mobile_ml_benchmark_2026-07-22/parity_comparison.json)
- [Mobile-to-mobile comparison](../../../test/out/final_mobile_ml_benchmark_2026-07-22/mobile_parity_comparison.json)

