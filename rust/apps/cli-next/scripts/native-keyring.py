#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(
    description="Build or test the CLI with native secret storage."
)
parser.add_argument(
    "mode",
    choices=["build", "test"],
    help="build prints the CLI path; test runs the keyring tests",
)
parser.add_argument(
    "--sign", metavar="IDENTITY", help="code-sign executables with this macOS identity"
)
args = parser.parse_args()
if args.mode == "build" and not args.sign:
    parser.error("build requires --sign")

app = Path(__file__).resolve().parent.parent
cargo = {
    "build": ["cargo", "build", "--bin", "ente-cli-next"],
    "test": ["cargo", "test", "--test", "cli", "--no-run"],
}[args.mode]
cargo += ["--locked", "--message-format=json-render-diagnostics"]
messages = subprocess.check_output(cargo, cwd=app, text=True)
executables = {}
for line in messages.splitlines():
    message = json.loads(line)
    if (
        message.get("executable")
        and Path(message["manifest_path"]).resolve() == app / "Cargo.toml"
    ):
        executables[message["target"]["kind"][0]] = message["executable"]

test_name = "native_keyring_survives_separate_processes"
if args.mode == "test":
    listing = subprocess.check_output(
        [executables["test"], "--ignored", "--exact", test_name, "--list"], text=True
    )
    if f"{test_name}: test" not in listing.splitlines():
        raise SystemExit("Native keyring test not found; nothing was run.")

if args.sign:
    # The test reads keys created by the CLI; both need the same development identity.
    subprocess.run(
        [
            "codesign",
            "--force",
            "--sign",
            args.sign,
            "--identifier",
            "io.ente.cli.dev",
            *executables.values(),
        ],
        check=True,
    )
    subprocess.run(["codesign", "--verify", "--strict", *executables.values()], check=True)

if args.mode == "test":
    subprocess.run([executables["test"]], check=True)
    subprocess.run(
        [executables["test"], "--ignored", "--exact", test_name], check=True
    )
else:
    print(executables["bin"])
