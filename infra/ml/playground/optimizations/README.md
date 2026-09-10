# Mobile ML model optimizations

This directory records the production transformations applied to Ente's mobile
ML models. The generated CDN artifacts are written under `models/`; ONNX files
are intentionally gitignored, while `model_manifest.json` records the
reproducible output metadata.

## OCR models

Generate one shared PP-OCRv5 detector, classifier, and recognizer for CoreML and
native WebGPU with:

```sh
uv run --no-project --with numpy==2.5.3 --with onnx==1.22.0 python \
  infra/ml/playground/optimizations/optimize_ocr_models.py \
  --source-dir infra/ml/playground/.cache/ocr-sources \
  --output-dir infra/ml/playground/optimizations/models/ocr
```

Missing source files are downloaded from `https://models.ente.com/PP-OCRv5`.
The script verifies every source hash and requires every generated model to
match the SHA-256 of its qualified artifact. It writes `det.onnx`, `cls.onnx`,
`rec.onnx`, the unchanged dictionary, and `ocr_model_manifest.json`. Both
platforms download identical model bytes. Upload the ONNX files to new versioned
URLs; the recognizer has a new output contract and must not replace the old URL.

The selected transformations are:

- Detection: fold the final transposed-convolution bias and batch normalization
  into the head weights. Preserve the original backbone affine expressions.
- Classification: canonicalize scalar affine constants and express 18 expanded
  activations as `HardSigmoid(alpha=1/6, beta=0.5) * x`.
- Recognition: canonicalize scalar affine constants, fold input affine operations
  into 12 unpadded convolutions, and replace four expanded normalization blocks
  with `LayerNormalization` using the original parameters and epsilon.
- Detection and recognition: expand `HardSwish` into
  `HardSigmoid(alpha=1/6, beta=0.5) * x` for CoreML compatibility.
- Recognition: pad the final weight matrix's 18,385 output columns to 18,432 for
  the existing WebGPU runtime's vectorized matrix multiplication, then slice
  back to 18,385 before the original bias and softmax.
- Recognition: reduce the original probabilities to the first winning token
  index and its probability for each time step, using FP32 arithmetic supported
  by both GPU providers.

The recognizer returns FP32 `[N,T,2]`, with index first and probability second.
For probabilities `p`, maximum `m`, vocabulary size `V`, and token index `i`, the
compact head computes `min(i + V * ceil(m - p[i]))`. Since probabilities are in
`[0,1]`, the ceiling is zero for maxima and one for every lower value. The
minimum therefore selects the first tied maximum without integer casts or
boolean selection. The other output is the original maximum probability.
See the [ONNX Ceil definition](https://onnx.ai/onnx/operators/onnx__Ceil.html).

The shared models retain FP32 parameters, vocabulary, CTC blank/repeat handling,
confidence averaging, and character-span rules. These transformations preserve
the mathematical operations but can introduce small floating-point differences.

The Rust OCR caller keeps its 960-pixel longest-side detector limit and existing
recognition crop sizes. It specializes sessions for actual dimensions without
changing input pixels and retains two detector shapes, six classifier batch
sizes, and eight recently used recognizer shapes.
CoreML uses MLProgram, CPUAndGPU, and disables low-precision GPU accumulation.
WebGPU uses NHWC internally for detection and NCHW for recognition. GPU session
construction requires full provider coverage; failures retry on a single CPU
thread. OCR never selects XNNPACK. Android classification uses the single-thread
CPU because it was faster than WebGPU on Pixel 8; it uses the same classifier
file as CoreML. Internal iOS uses CoreML for all three stages.

Qualification uses unchanged ONNX Runtime 1.28.1 on Pixel 8 with native
Dawn/Vulkan WebGPU and Apple M4 with CoreML. The saved model comparison covers
317 crop sources from 17 unique photos, 21,256 recognition time steps, 320
classification inputs, and 9,383,936 detector probabilities. Neither provider
changed any winning token, orientation decision, or detector threshold decision
in those cases. Every CoreML case formed one complete partition using GPU
compute devices; both providers completed with CPU fallback disabled. Separate
compact output checks matched all 144 rows exactly, including ties, uniform
probabilities, and adjacent FP32 values. These checks do not establish bit-identical outputs on
all images or performance on an iPhone. Smaller detector inputs were excluded
because they missed text in the supplied photos.

The shared artifacts produced these warm native inference medians on 10
September 2026. Each range contains two trial medians, with 40 calls per trial
and the first 10 discarded. Runs use one CPU inference thread and include the
normal CPU input/output transfer; model loading, compilation, image decoding,
and Rust preprocessing/postprocessing are excluded. CoreML measurements are
from an Apple M4 Mac, not an iPhone.

| Stage and NCHW input | M4 CoreML GPU | Pixel 8 native WebGPU |
| --- | ---: | ---: |
| Empty-image detection, 1×3×960×704 | 10.4–10.9 ms | 128.6–132.2 ms |
| Empty-image detection, 1×3×960×960 | 13.3–13.6 ms | 173.3–175.0 ms |
| Classification, 6×3×48×192 | 1.4–2.0 ms | 19.3–33.9 ms |
| Recognition, 6×3×48×320 | 9.5–9.6 ms | 104.1–104.8 ms |
| Recognition, 6×3×48×640 | 16.8–17.0 ms | 189.5–190.4 ms |

The same classifier took 8.7–8.8 ms on the Pixel's single-thread CPU, which is
why the Android caller keeps that stage on CPU. Both uniform-gray detection
inputs produced no pixels at or above the 0.3 threshold.

## Rebuilding the models

Run from the repository root:

```sh
uv run --project infra/ml/playground --no-sync python \
  infra/ml/playground/optimizations/optimize_models.py \
  --source-dir infra/ml/test/.cache/local_model_mirror \
  --output-dir infra/ml/playground/optimizations/models
```

The script performs only the transformations selected for production:

- YOLO: fix the batch dimension at 1 and use ONNX Runtime's basic optimizer to
  constant-fold the resulting shape graph.
- MobileFaceNet: fix the batch dimension at 1 and express each of its 33 trained
  PReLU activations exactly as `Relu(x) - alpha * Relu(x * -1)`. This avoids a
  WebGPU-only runtime kernel while using operators supported by both CoreML
  MLProgram and WebGPU, so the generated artifact can be shared by Android and
  iOS. The script also makes two implicit zero-padding attributes explicit and
  removes the final L2 normalization that the Rust caller already performs.
- MobileCLIP: convert the graph to ONNX opset 20 and replace 54 expanded exact
  GELU expressions with `Gelu(approximate="none")`. This keeps FP32/exact GELU
  semantics while exposing the fused operator to CoreML and WebGPU.

The script verifies the source-model hashes and emits the three ONNX files plus
`model_manifest.json`, which records their output hashes, shapes, sizes, node
counts, and operator inventories.
