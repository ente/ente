"""Path resolution shared by the parity tools.

Importing this module also puts the ML test directory on sys.path so that
sibling scripts can import the `ground_truth` and `comparator` packages.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ML_DIR = Path(__file__).resolve().parents[1]
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))


def repo_root() -> Path:
    try:
        completed = subprocess.run(
            ["git", "-C", str(ML_DIR), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return ML_DIR.parents[2]
    root = completed.stdout.strip()
    if not root:
        return ML_DIR.parents[2]
    return Path(root)


def resolve_repo_relative(path_value: str, *, repo_root: Path) -> Path:
    path = Path(path_value)
    if path.is_absolute():
        return path
    return repo_root / path


def resolve_ml_relative(path_value: str) -> Path:
    path = Path(path_value)
    if path.is_absolute():
        return path
    return ML_DIR / path
