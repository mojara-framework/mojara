# Build Mojara from GitHub source

The GitHub repository contains Mojara's first-party Mojo framework, native CLI, C/C++ bridges and build instructions. Use these steps when you want to inspect, modify or compile the framework itself. For ordinary application development, use the packaged [installation](INSTALL-LINUX.md) or the [Docker image](DOCKER.md).

## Linux x86-64 and Linux ARM64

Install the native build tools on Ubuntu 24.04:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates build-essential \
  pkg-config python3 patch patchelf binutils
```

Install [Pixi](https://pixi.sh/latest/installation/) and clone the source:

```bash
curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

git clone https://github.com/mojara-framework/mojara.git
cd mojara
pixi install
```

Build the entire first-party framework and CLI:

```bash
pixi run bash scripts/ci/bootstrap-source.sh
pixi run bash scripts/ci/build-source-sdk.sh
```

The first command downloads Flare, JSON, Morph and SQLite from independently pinned upstream Git revisions, checks their archive hashes, and applies the recorded Mojara compatibility changes. The second builds native libraries, the Mojara CLI and the complete Mojo framework for your current architecture.

The resulting SDK is inside `build/full-integration/sdk/`, including `bin/mojara`, `lib/mojo/mojara.mojoc` and the compiled native bridges.

Configure the current terminal to use that locally compiled SDK:

```bash
export MOJARA_HOME="$PWD/build/full-integration/sdk"
export PATH="$MOJARA_HOME/bin:$PWD/.pixi/envs/default/bin:$PATH"
export LD_LIBRARY_PATH="$MOJARA_HOME/lib:$PWD/.pixi/envs/default/lib:${LD_LIBRARY_PATH:-}"

mojara version
mojara doctor
```

Create and run an application using your locally compiled Mojara:

```bash
mojara new hello-from-source
cd hello-from-source
mojara build
mojara start --local
```

Open `http://localhost:8000`.

## macOS Apple Silicon

Install Apple's Command Line Tools and [Pixi](https://pixi.sh/latest/installation/):

```bash
xcode-select --install
curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"
git clone https://github.com/mojara-framework/mojara.git
cd mojara
pixi install
```

Compile the Apple Silicon native Mach-O libraries and Mojara Mojo framework:

```bash
pixi run bash scripts/ci/bootstrap-source.sh
pixi run bash scripts/ci/build-macos-sdk.sh
```

Use the locally built SDK:

```bash
export MOJARA_HOME="$PWD/build/full-integration/sdk"
export PATH="$MOJARA_HOME/bin:$PWD/.pixi/envs/default/bin:$PATH"
export DYLD_LIBRARY_PATH="$MOJARA_HOME/lib:$PWD/.pixi/envs/default/lib:${DYLD_LIBRARY_PATH:-}"

mojara doctor
mojara new hello-from-source
cd hello-from-source
mojara build
mojara start --local
```

## Windows and Intel Macs

For Windows 10/11, run the **Linux** instructions above inside WSL2 Ubuntu.

For Intel Macs, use the supported [Docker installation](DOCKER.md) to compile and run Mojo applications inside a Linux x86-64 environment. The upstream native Mojo compiler is currently available for Apple Silicon Macs, not Intel macOS.

## Source inventory and reproducibility

- `source/mojara/`: public Mojo framework modules.
- `source/cli/mojara_cli.mojo`: native command-line application.
- `source/native/`: native C bridge implementations.
- `source/upstream/UPSTREAM.lock`: exact Git commits and upstream archive SHA-256 values.
- `source/upstream/compat.patch`: tracked platform and API compatibility changes.
- `source/upstream/source-sha256.txt`: exact upstream source-file inventory.

These steps compile the first-party framework from source and do not download a previously compiled Mojara SDK. Native transaction-pool extension provenance is tracked separately in [issue #3](https://github.com/mojara-framework/mojara/issues/3).

To build distributable Conda packages rather than a local SDK, see the [release build scripts](../scripts/ci/) and [release checklist](RELEASE-CHECKLIST.md).
