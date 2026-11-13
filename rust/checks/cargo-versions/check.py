import re
import subprocess
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sections = "dependencies", "dev-dependencies", "build-dependencies"
complete = re.compile(
    r"(?:\^|~|=|>=|>|<=|<)?\s*[0-9]+\.[0-9]+\.[0-9]+"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)
manifest_paths = subprocess.check_output(
    [
        "git",
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "-z",
        "--",
        "rust/Cargo.toml",
        "rust/**/Cargo.toml",
    ],
    cwd=root,
    text=True,
).split("\0")
manifests = sorted(
    root / path for path in manifest_paths if path and (root / path).is_file()
)
if not manifests:
    raise SystemExit(f"{root}/rust: found no Cargo manifests")
failed = False

for manifest in manifests:
    path = manifest.relative_to(root).as_posix()
    cargo = tomllib.loads(manifest.read_text())
    tables = [(section, cargo.get(section, {})) for section in sections]
    tables += [
        (f"target.{target}.{section}", config.get(section, {}))
        for target, config in cargo.get("target", {}).items()
        for section in sections
    ]
    tables.append(
        ("workspace.dependencies", cargo.get("workspace", {}).get("dependencies", {}))
    )
    for table, dependencies in tables:
        for name, declaration in dependencies.items():
            requirement = (
                declaration if isinstance(declaration, str) else declaration.get("version")
            )
            if requirement is None:
                continue
            if all(complete.fullmatch(part.strip()) for part in requirement.split(",")):
                continue
            print(
                f"{path}: {table}.{name} has incomplete version requirement {requirement!r}",
                file=sys.stderr,
            )
            failed = True

sys.exit(1 if failed else 0)
