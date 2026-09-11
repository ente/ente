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

The script produces three shared FP32 models (23.17 MB total) with fixed inputs:

- Detection: a 960×960 canvas with five fixed computation paths. Masks preserve
  the original image boundaries and pooling when selecting a smaller path.
- Classification: six 48×192 crops; Rust pads incomplete batches.
- Recognition: a 48×7168 canvas with 2048- and 7168-wide paths. Rust packs lines;
  masks isolate their convolutions, pooling, and attention. Aligned matrix
  operations return winning token indices and probabilities for Rust CTC decoding.

Affine folding and equivalent activation rewrites improve GPU support. Shared
weights keep the fixed paths compact. These models require the matching Rust
input adapter; they cannot replace the original models independently.

Missing sources are downloaded from `https://models.ente.com/PP-OCRv5`. Source and
output hashes are verified. Upload only `det_fixed_v1.onnx`, `cls_fixed_v1.onnx`,
and `rec_fixed_v1.onnx`; the dictionary is unchanged. The generated
`ocr_model_manifest.json` records the input shapes, hashes, and sizes.

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
