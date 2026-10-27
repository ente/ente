# Install Ente CLI

Download the archive for your system from the latest [Ente CLI release](https://github.com/ente/ente/releases?q=tag%3Aente-cli-v0), verify it, extract the `ente` executable, and run `ente --version`.

| System              | Archive name ends with |
| ------------------- | ---------------------- |
| Linux x86_64        | `-linux-amd64.tar.gz`  |
| Linux ARM64         | `-linux-arm64.tar.gz`  |
| macOS Intel         | `-darwin-amd64.tar.gz` |
| macOS Apple silicon | `-darwin-arm64.tar.gz` |
| Windows x86_64      | `-windows-amd64.zip`   |
| Windows ARM64       | `-windows-arm64.zip`   |

Each archive contains one file, the executable. There are no 32-bit builds.

**On Linux and macOS:** download the archive and `SHA256SUMS` from the release page, then:

```sh
cd ~/Downloads
shasum -a 256 --check --ignore-missing SHA256SUMS
mkdir -p ~/.local/opt/ente-cli/bin
tar -xzf ente-cli-vX.Y.Z-linux-amd64.tar.gz -C ~/.local/opt/ente-cli/bin
~/.local/opt/ente-cli/bin/ente --version
```

Use the name of the archive you downloaded. On Linux, `sha256sum --check --ignore-missing SHA256SUMS` works as well. The check prints `OK` after the archive name, and the last command prints `ente` followed by the version.

On Linux, keep the CLI in its own directory: `/usr/bin/ente` may belong to the Ente Photos desktop app.

On macOS, if you downloaded the archive with a browser, the first run is refused. Remove the quarantine flag, then run it again:

```sh
xattr -d com.apple.quarantine ~/.local/opt/ente-cli/bin/ente
```

**On Windows (PowerShell):** download the archive and `SHA256SUMS` from the release page, then:

```powershell
cd ~\Downloads
(Get-FileHash ente-cli-vX.Y.Z-windows-amd64.zip).Hash.ToLower()
Select-String windows-amd64 SHA256SUMS
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Programs\EnteCLI" | Out-Null
Expand-Archive ente-cli-vX.Y.Z-windows-amd64.zip -DestinationPath "$env:LOCALAPPDATA\Programs\EnteCLI"
& "$env:LOCALAPPDATA\Programs\EnteCLI\ente.exe" --version
```

Use the name of the archive you downloaded. The two hashes must match, and the last command prints `ente` followed by the version.

## Add the CLI to your PATH

**On Linux and macOS:** add this line to your shell startup file (`~/.bashrc`, `~/.zshrc` or `~/.config/fish/config.fish`), then open a new terminal:

```sh
export PATH="$HOME/.local/opt/ente-cli/bin:$PATH"
```

In fish, use `fish_add_path ~/.local/opt/ente-cli/bin` instead.

**On Windows:** run this once, then open a new terminal:

```powershell
[Environment]::SetEnvironmentVariable("Path", "$env:LOCALAPPDATA\Programs\EnteCLI;" + [Environment]::GetEnvironmentVariable("Path", "User"), "User")
```

## Enable completion

Add the line for your shell to its startup file:

| Shell      | Startup file              | Line                                                             |
| ---------- | ------------------------- | ---------------------------------------------------------------- |
| Bash       | `~/.bashrc`               | `eval "$(ente completion bash)"`                                 |
| Zsh        | `~/.zshrc`                | `autoload -Uz compinit; compinit; source <(ente completion zsh)` |
| PowerShell | `$PROFILE`                | `ente completion powershell \| Out-String \| Invoke-Expression`  |
| Elvish     | `~/.config/elvish/rc.elv` | `eval (ente completion elvish \| slurp)`                         |

Fish loads a saved script. Write it once, and again after updating:

```sh
mkdir -p ~/.config/fish/completions
ente completion fish > ~/.config/fish/completions/ente.fish
```

## Update

Download the new archive, verify it, and extract it over the existing executable (on Windows, add `-Force` to `Expand-Archive`). `ente --version` prints the new version. Your accounts and data stay in the CLI home (see [Accounts](./accounts.md#cli-home)).

## Uninstall

Log out of each account first if you want the server to forget this device: `ente account logout --account NAME`. Then delete the directory that holds the executable, remove the PATH line, and delete the CLI home.

## Build from source

```sh
git clone https://github.com/ente/ente.git
cd ente
git checkout ente-cli-vX.Y.Z
cd rust
cargo install --locked --path apps/cli --root ~/.local/opt/ente-cli
```

Use the tag of the release you want, as shown on its release page. The executable is written to `~/.local/opt/ente-cli/bin/ente`.
