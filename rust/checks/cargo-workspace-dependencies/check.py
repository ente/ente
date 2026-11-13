import json
import subprocess
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sections = "dependencies", "dev-dependencies", "build-dependencies"
metadata = json.loads(
    subprocess.check_output(
        [
            "cargo",
            "metadata",
            "--no-deps",
            "--format-version",
            "1",
            "--locked",
            "--offline",
        ],
        cwd=root / "rust",
        text=True,
    )
)
packages = [
    package for package in metadata["packages"]
    if package["id"] in metadata["workspace_members"]
]
users = {}
for package in packages:
    for dependency in package["dependencies"]:
        users.setdefault(dependency["name"], set()).add(package["id"])

failed = False


def check_order(entries, path, table):
    entries = list(entries)
    for previous, current in zip(entries, entries[1:]):
        if previous > current:
            print(
                f"{path}: {table} must be sorted: {previous!r} precedes {current!r}",
                file=sys.stderr,
            )
            return False
    return True


workspace = tomllib.loads((root / "rust/Cargo.toml").read_text())["workspace"]
for table in ("members", "dependencies"):
    failed |= not check_order(workspace.get(table, {}), "rust/Cargo.toml", f"workspace.{table}")

for package in packages:
    manifest = Path(package["manifest_path"])
    path = manifest.relative_to(root).as_posix()
    cargo = tomllib.loads(manifest.read_text())
    if cargo["package"].get("edition") != {"workspace": True}:
        print(f"{path}: use edition.workspace = true", file=sys.stderr)
        failed = True
    if cargo.get("lints") != {"workspace": True}:
        print(f"{path}: use [lints] workspace = true", file=sys.stderr)
        failed = True
    tables = [(section, cargo.get(section, {})) for section in sections]
    tables += [
        (f"target.{target}.{section}", config.get(section, {}))
        for target, config in cargo.get("target", {}).items()
        for section in sections
    ]
    for table, dependencies in tables:
        failed |= not check_order(dependencies, path, table)
        for name, declaration in dependencies.items():
            if isinstance(declaration, dict) and declaration.get("workspace") is True:
                continue
            dependency = (
                declaration.get("package", name) if isinstance(declaration, dict) else name
            )
            if len(users[dependency]) < 2:
                continue
            print(
                f"{path}: {table}.{name} duplicates shared dependency {dependency!r}; use workspace = true",
                file=sys.stderr,
            )
            failed = True
    failed |= not check_order(cargo.get("features", {}), path, "features")

sys.exit(1 if failed else 0)
