import subprocess
import sys
import tempfile
from pathlib import Path

check = Path(__file__).with_name("check.py")
workspace = """\
[workspace]
members = ["app-*"]
exclude = ["app-excluded"]
resolver = "2"

[workspace.package]
edition = "2024"

[workspace.dependencies]
serde = "1.0.0"
shared = { path = "shared" }

[workspace.lints.clippy]
allow_attributes = "deny"
allow_attributes_without_reason = "deny"
"""
package = """\
[package]
name = "{}"
version = "0.1.0"
edition.workspace = true

[lints]
workspace = true
"""


def run(app_b, members='"app-*"', app_b_package=package, workspace_toml=workspace):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        rust = root / "rust"
        write(rust / "Cargo.toml", workspace_toml.replace('"app-*"', members))
        write(
            rust / "app-a/Cargo.toml",
            package.format("app-a")
            + "\n[dependencies]\nserde.workspace = true\nshared.workspace = true\n",
        )
        write(rust / "app-b/Cargo.toml", app_b_package.format("app-b") + app_b)
        write(
            rust / "app-excluded/Cargo.toml",
            '[package]\nname = "app-excluded"\nversion = "0.1.0"\nedition = "2024"\n'
            + '\n[dependencies]\nsolo = { path = "../solo" }\n',
        )
        write(rust / "shared/Cargo.toml", package.format("shared"))
        write(rust / "solo/Cargo.toml", package.format("solo"))
        return subprocess.run(
            [sys.executable, check, root],
            capture_output=True,
            text=True,
        )


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if path.name == "Cargo.toml" and path.parent.name != "rust":
        source = path.parent / "src/lib.rs"
        source.parent.mkdir(exist_ok=True)
        source.write_text("")


result = run('\n[dependencies]\nshared = { path = "../shared" }\n')
assert result.returncode == 1, result.stderr
assert "dependencies.shared duplicates shared dependency 'shared'" in result.stderr

result = run("\n[dependencies]\nshared.workspace = true\n")
assert result.returncode == 0, result.stderr
assert not result.stdout
assert not result.stderr

result = run(
    '\n[target.\'cfg(unix)\'.dev-dependencies]\nlocal = { package = "shared", path = "../shared" }\n'
)
assert result.returncode == 1, result.stderr
assert "target.cfg(unix).dev-dependencies.local" in result.stderr

result = run('''
[dependencies]
solo = { path = "../solo" }
[dev-dependencies]
solo = { path = "../solo" }
''')
assert result.returncode == 0, result.stderr
assert not result.stdout
assert not result.stderr

result = run('''
[target.'cfg(unix)'.dependencies]
dep = { package = "serde", version = "1.0.0" }
[target.'cfg(windows)'.dependencies]
dep = { package = "tokio", version = "1.0.0" }
''')
assert result.returncode == 1, result.stderr
assert "target.cfg(unix).dependencies.dep duplicates shared dependency 'serde'" in result.stderr
assert "target.cfg(windows)" not in result.stderr

result = run("\n[dependencies]\nshared.workspace = true\n", '"app-b", "app-a"')
assert result.returncode == 1, result.stderr
assert "rust/Cargo.toml: workspace.members must be sorted: 'app-b' precedes 'app-a'" in result.stderr

result = run("\n[dependencies]\nshared.workspace = true\n", '"app-a", "app-b"')
assert result.returncode == 0, result.stderr
assert not result.stderr

result = run("", app_b_package=package.replace('edition.workspace = true', 'edition = "2024"'))
assert result.returncode == 1, result.stderr
assert "rust/app-b/Cargo.toml: use edition.workspace = true" in result.stderr

result = run("", app_b_package=package.replace("\n[lints]\nworkspace = true\n", ""))
assert result.returncode == 1, result.stderr
assert "rust/app-b/Cargo.toml: use [lints] workspace = true" in result.stderr

for section in (
    "dependencies",
    "dev-dependencies",
    "build-dependencies",
    "target.'cfg(unix)'.dependencies",
):
    result = run(f"\n[{section}]\nshared.workspace = true\nserde.workspace = true\n")
    assert result.returncode == 1, result.stderr
    table = section.replace("'", "")
    assert f"{table} must be sorted" in result.stderr

result = run("", workspace_toml=workspace.replace(
    'serde = "1.0.0"\nshared = { path = "shared" }',
    'shared = { path = "shared" }\nserde = "1.0.0"',
))
assert result.returncode == 1, result.stderr
assert "workspace.dependencies must be sorted" in result.stderr

result = run("\n[features]\nzeta = []\nalpha = []\n")
assert result.returncode == 1, result.stderr
assert "features must be sorted" in result.stderr

result = run("\n[features]\nalpha = []\nzeta = []\n")
assert result.returncode == 0, result.stderr
