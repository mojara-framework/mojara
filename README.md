# Mojara 🔥

**A native web framework for Mojo.**

Mojara brings routing, HTTP APIs, templates, authentication, sessions, cookies, file uploads, WebSockets, MySQL, PostgreSQL, SQLite and more to applications written in Mojo. Performance-sensitive adapters use native C/C++ libraries.

[Documentation](https://mojara.kasua.ng/docs/) · [Full API reference](docs/API-REFERENCE.md) · [Quickstart](https://mojara.kasua.ng/docs/quickstart.html) · [Docker](docs/DOCKER.md) · [Build from source](docs/BUILD-FROM-SOURCE.md) · [Changelog](CHANGELOG.md)

## Installation

Mojara **1.2.7** is available through Pixi and Docker. Install the framework using your operating system's instructions below. You only need to clone this GitHub repository if you want to compile or contribute to Mojara itself.

### Linux (x86-64 and ARM64)

Install [Pixi](https://pixi.sh/latest/installation/), then install Mojara globally:

```bash
curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge

mojara version
mojara doctor
```

The package manager installs Mojara and the compatible Mojo compiler. No repository clone or project-level Pixi setup is required.

### Windows 10/11 (WSL2 Ubuntu)

Open **PowerShell as Administrator** and install Ubuntu:

```powershell
wsl --install -d Ubuntu-24.04
```

After Ubuntu's first-time setup, open its terminal and run the **Linux installation commands above inside Ubuntu**, not in PowerShell. Run Mojara applications from the Linux filesystem for faster compilation.

```bash
mojara new hello-mojara
cd hello-mojara
mojara dev
```

Open `http://localhost:8000` in your Windows browser. Mojara runs through WSL2's supported Linux toolchain. [Windows details](docs/WINDOWS.md).

### macOS Apple Silicon (M1 and newer)

Install [Pixi](https://pixi.sh/latest/installation/) in your Mac terminal:

```bash
curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge

mojara doctor
```

This installs the native Apple Silicon Mojara package and Mojo compiler.

### macOS Intel — Docker Desktop

Intel Macs run the official Linux x86-64 Mojara image inside [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/). Install and start Docker Desktop, then:

```bash
docker pull --platform linux/amd64 ghcr.io/mojara-framework/mojara:1.2.7

mkdir -p "$HOME/.local/bin"
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/macos/mojara-intel.sh \
  -o "$HOME/.local/bin/mojara"
chmod +x "$HOME/.local/bin/mojara"
export PATH="$HOME/.local/bin:$PATH"

mojara version
mojara doctor
mojara new hello-mojara
cd hello-mojara
mojara dev
```

Open `http://localhost:8000`. The launcher preserves files in your Mac directory and runs the compiler in Linux. Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc` to make the command available in new terminal sessions.

**Intel CPU requirement:** Linux Mojo requires an x86-64-v3-capable processor (including AVX2). Older Intel Macs that do not meet this requirement cannot run Mojo in Docker.

### macOS Intel — without Docker (Lima VM)

An alternative is a lightweight [Lima](https://lima-vm.io/) Ubuntu virtual machine. Install [Homebrew](https://brew.sh/), then:

```bash
brew install lima
limactl start --name=mojara-linux template:ubuntu
limactl shell mojara-linux
```

Inside the Ubuntu shell, install the compiler's linker and Pixi, then Mojara:

```bash
sudo apt update
sudo apt install -y build-essential curl ca-certificates

curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
pixi global install 'watchexec>=2.7,<3' -c conda-forge

mojara new hello-mojara
cd hello-mojara
MOJARA_HOST=0.0.0.0 mojara dev
```

Lima exposes the application at `http://localhost:8000`. This is Linux VM support, **not a native Intel macOS compiler**. The same Intel processor requirements apply. [Full macOS guide](docs/INSTALL-MACOS.md).

## Install with Docker on any supported CPU

Official multi-architecture image: **`ghcr.io/mojara-framework/mojara`**, with published `1.2.7` and `latest` tags for Linux AMD64 and ARM64. Docker selects the matching architecture.

```bash
docker pull ghcr.io/mojara-framework/mojara:1.2.7
docker run --rm ghcr.io/mojara-framework/mojara:1.2.7 version
```

Create a project in your current directory:

```bash
docker run --rm -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.7 new hello-mojara

cd hello-mojara
```

Develop with hot reload and access your app in the browser:

```bash
docker run --rm -it \
  -p 127.0.0.1:8000:8000 \
  -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.7 dev
```

Compile an application:

```bash
docker run --rm -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.7 build
```

To run a compiled application, replace `build` with `start --local` and add the same `-p 127.0.0.1:8000:8000` port mapping. The [Docker guide](docs/DOCKER.md) also covers Docker Compose, image tags and configuration.

## Create your first application

When installed natively through Pixi:

```bash
mojara new hello-mojara
cd hello-mojara
mojara dev
```

Visit `http://localhost:8000`. Create a JSON API instead with `mojara new hello-api --api`. Compile and serve with:

```bash
mojara build
mojara start --local
```

The `new` command creates an application directly under the current directory, without a nested project or another `pixi.toml`. See the [step-by-step tutorial](https://mojara.kasua.ng/docs/tutorial.html) and [CLI guide](https://mojara.kasua.ng/docs/cli.html).

## Compile Mojara itself from GitHub

This section is for developers who want the **actual framework source** rather than installing the released package. The repository contains the Mojo framework, CLI and first-party native C/C++ bridge source. External Mojo dependencies are retrieved from independently pinned upstream revisions, with checksum verification.

### Linux x86-64 / Linux ARM64 / Windows through WSL2

On Ubuntu 24.04:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates build-essential \
  pkg-config python3 patch patchelf binutils

curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

git clone https://github.com/mojara-framework/mojara.git
cd mojara
pixi install
pixi run bash scripts/ci/bootstrap-source.sh
pixi run bash scripts/ci/build-source-sdk.sh
```

Your compiled SDK is created at `build/full-integration/sdk/`. To use it:

```bash
export MOJARA_HOME="$PWD/build/full-integration/sdk"
export PATH="$MOJARA_HOME/bin:$PWD/.pixi/envs/default/bin:$PATH"
export LD_LIBRARY_PATH="$MOJARA_HOME/lib:$PWD/.pixi/envs/default/lib:${LD_LIBRARY_PATH:-}"
mojara doctor
```

### macOS Apple Silicon source build

Install Xcode Command Line Tools and Pixi, then:

```bash
xcode-select --install
curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

git clone https://github.com/mojara-framework/mojara.git
cd mojara
pixi install
pixi run bash scripts/ci/bootstrap-source.sh
pixi run bash scripts/ci/build-macos-sdk.sh
```

To use your freshly compiled SDK:

```bash
export MOJARA_HOME="$PWD/build/full-integration/sdk"
export PATH="$MOJARA_HOME/bin:$PWD/.pixi/envs/default/bin:$PATH"
export DYLD_LIBRARY_PATH="$MOJARA_HOME/lib:$PWD/.pixi/envs/default/lib:${DYLD_LIBRARY_PATH:-}"
mojara doctor
```

See [Build from source](docs/BUILD-FROM-SOURCE.md) for source layout, compiler requirements and complete examples.

## Supported platforms

| Platform | Mojara |
| --- | --- |
| Linux x86-64 | **Supported** |
| Linux ARM64 | **Supported** |
| Windows 10/11 through WSL2 Ubuntu | **Supported** |
| macOS Apple Silicon | **Supported** |
| macOS Intel through Docker (Linux x86-64) | **Supported** |
| macOS Intel through Lima (Linux VM) | Linux VM installation available |
| Native Windows executables | Not yet available |
| Native macOS Intel compiler | Not provided by upstream Mojo |

## Features

- Routing, middleware, HTTP APIs and JSON responses
- HTML templates, static files, form parsing and uploads
- Authentication, sessions, cookies and security utilities
- WebSockets, streaming and native networking
- MySQL, PostgreSQL, SQLite, migrations and database pools
- Native Mojo CLI, source compilation, hot reload and deployment

## Repository structure

```text
source/mojara/         First-party Mojo framework
source/cli/           Native Mojo command-line tool
source/native/        Native C/C++ bridges
source/upstream/      Pinned external Mojo source and compatibility patches
packaging/conda/      Native package recipes
packaging/docker/     Multiarchitecture Docker image
scripts/              Framework builds, verification and packaging
docs/                 Tutorials and full API reference
```

Read the [complete API reference](docs/API-REFERENCE.md), [contribution guide](CONTRIBUTING.md) and [security policy](SECURITY.md).

Mojara is released under the [MIT License](LICENSE). Third-party licenses are preserved in [the dependency notices](docs/THIRD_PARTY_LICENSES.md).
