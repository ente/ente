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

The script keeps FP32 weights and applies these transformations:

- Detection: fold the transposed-convolution head's bias and batch normalization,
  and expand `HardSwish` into `HardSigmoid * x` for CoreML compatibility.
- Classification: canonicalize scalar constants and simplify expanded activations
  to `HardSigmoid * x`.
- Recognition: fold affine operations into unpadded convolutions, fuse layer
  normalization, expand `HardSwish`, and align the final matrix multiplication
  for WebGPU without changing the vocabulary. Return FP32 `[N,T,2]` containing
  the first winning token index and its probability; Rust retains CTC decoding.

Missing sources are downloaded from `https://models.ente.com/PP-OCRv5`. The script
verifies source and output hashes and writes three ONNX files, the unchanged
dictionary, and `ocr_model_manifest.json`. Publish the ONNX files at new URLs:
the recognizer's output contract differs from the original model.

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
