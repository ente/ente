import subprocess
import sys
import tempfile
from pathlib import Path

check = Path(__file__).with_name("check.py")


def run(current, added=None, ignored=None, deleted=False):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        manifest = root / "rust/app/Cargo.toml"
        if current is None:
            (root / ".gitignore").write_text("")
        else:
            manifest.parent.mkdir(parents=True)
            manifest.write_text(current)
        if ignored:
            (root / ".gitignore").write_text("/rust/target/\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        if deleted:
            manifest.unlink()
        if added:
            new_manifest = root / "rust/new/Cargo.toml"
            new_manifest.parent.mkdir()
            new_manifest.write_text(added)
        if ignored:
            ignored_manifest = root / "rust/target/package/generated/Cargo.toml"
            ignored_manifest.parent.mkdir(parents=True)
            ignored_manifest.write_text(ignored)
        return subprocess.run(
            [sys.executable, check, root],
            capture_output=True,
            text=True,
        )


failing = """\
[package]
name = "fixture"
version = "0.1.0"

[dependencies]
legacy = "1.2"
metadata = { version = "2", features = ["new"] }
changed = "3.5"
substring = "1.2.3.4"
wildcard = "1.2.*"
incomplete_range = ">=1.2.3, <2"
complete = "1.2.3"
range = ">=1.2.3, <2.0.0"
prerelease = "^3.4.5-alpha.1+build.2"
local = { path = "../local" }

[dev-dependencies]
dev = "4.5"

[build-dependencies]
build = { version = "5" }

[target.'cfg(unix)'.dependencies]
target = "6.7"

[target.'cfg(unix)'.dev-dependencies]
target_dev = "7"

[target.'cfg(unix)'.build-dependencies]
target_build = "8.9"

[workspace.dependencies]
workspace = "9"
"""
result = run(failing, '[dependencies]\nnew_manifest = "10.11"\n')
assert result.returncode == 1, result.stderr
for dependency in (
    "dependencies.legacy",
    "dependencies.metadata",
    "dependencies.changed",
    "dependencies.substring",
    "dependencies.wildcard",
    "dependencies.incomplete_range",
    "dev-dependencies.dev",
    "build-dependencies.build",
    "target.cfg(unix).dependencies.target",
    "target.cfg(unix).dev-dependencies.target_dev",
    "target.cfg(unix).build-dependencies.target_build",
    "workspace.dependencies.workspace",
    "dependencies.new_manifest",
):
    assert f": {dependency} has" in result.stderr, (dependency, result.stderr)
for dependency in (
    "dependencies.complete",
    "dependencies.range",
    "dependencies.prerelease",
    "dependencies.local",
):
    assert f": {dependency} has" not in result.stderr, (dependency, result.stderr)

passing = """\
[package]
name = "fixture"
version = "0.1.0"

[dependencies]
legacy = "1.2.0"
metadata = { version = "2.0.0", features = ["new"] }
changed = "3.4.5"
complete = "1.2.3"
range = ">=1.2.3, <2.0.0"
prerelease = "^3.4.5-alpha.1+build.2"
local = { path = "../local" }

[workspace.dependencies]
workspace = "9.0.0"
"""
result = run(passing, '[target.\'cfg(unix)\'.dependencies]\nnew_manifest = "10.11.12"\n')
assert result.returncode == 0, result.stderr
assert not result.stdout
assert not result.stderr

assert run("[dependencies\nbroken = '1.2.3'\n").returncode != 0
result = run(None)
assert result.returncode != 0
assert "found no Cargo manifests" in result.stderr
result = run(passing, ignored='[dependencies]\ngenerated = "1"\n')
assert result.returncode == 0, result.stderr
result = run(failing, added=passing, deleted=True)
assert result.returncode == 0, result.stderr
