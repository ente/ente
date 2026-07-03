# ML Playground

This directory is for exploratory and model-preparation work only.

Current contents include:

- `CLIP/`: CLIP/mobileclip notebooks and experiments.
- `YOLOv5Face/`: YOLOv5Face notebooks and related assets.
- `data/`: local sample images used by notebooks.

## Running notebooks

1. Install `uv`.
2. From repo root, run `uv sync --project infra/ml/playground`.
3. In VS Code/Jupyter, use kernel `infra/ml/playground/.venv/bin/python`.

## Notebook hygiene

Clear notebook outputs before committing to keep diffs readable and stable.
