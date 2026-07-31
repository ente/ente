# Mobile ML model optimizations

This directory records the production transformations applied to Ente's mobile
ML models. The generated CDN artifacts are written under `models/`; ONNX files
are intentionally gitignored, while `model_manifest.json` records the
reproducible output metadata.

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
