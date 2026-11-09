# Mojara 🔥

**A native web framework for Mojo.**

Mojara brings routing, HTTP APIs, templates, authentication, sessions, cookies, file uploads, WebSockets, MySQL, PostgreSQL, SQLite and more to applications written in Mojo. Performance-sensitive adapters use native C/C++ libraries.

[Documentation](https://mojara.kasua.ng/docs/) · [Full API reference](docs/API-REFERENCE.md) · [Quickstart](https://mojara.kasua.ng/docs/quickstart.html) · [Docker](docs/DOCKER.md) · [Build from source](docs/BUILD-FROM-SOURCE.md) · [Changelog](CHANGELOG.md)

## Installation

Mojara **1.2.7** is available through Pixi and Docker. Install the framework using your operating system's instructions below. You only need to clone this GitHub repository if you want to compile or contribute to Mojara itself.

### Linux (x86-64 and ARM64)

**Step 1 — Install [Pixi](https://pixi.sh/latest/installation/).**

```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

**Step 2 — Enable Pixi in the current terminal.**

```bash
export PATH="$HOME/.pixi/bin:$PATH"
```

**Step 3 — Install Mojara.**

```bash
pixi global install 'mojara==1.2.7' -c https://mojara.kasua.ng/conda/ -c https://conda.modular.com/max/ -c conda-forge
```

**Step 4 — Verify Mojara.**

```bash
mojara version
```

```bash
mojara doctor
```

Pixi installs Mojara and the compatible Mojo compiler. No repository clone or project-level Pixi setup is required.

### Windows 10/11 (WSL2 Ubuntu)

**Step 1 — Open PowerShell as Administrator and install Ubuntu.**

```powershell
wsl --install -d Ubuntu-24.04
```

**Step 2 — Open the Ubuntu terminal.** Complete the Ubuntu account setup, then follow the Linux installation steps above **inside Ubuntu**, not PowerShell.

**Step 3 — Create your first Mojara project.**

```bash
mojara new hello-mojara
```

**Step 4 — Enter the project folder.**

```bash
cd hello-mojara
```

**Step 5 — Start the development server.**

```bash
mojara dev
```

Open `http://localhost:8000` in your Windows browser. Keep projects on the Linux filesystem for faster compilation. [Windows setup](docs/WINDOWS.md).

### macOS Apple Silicon (M1 and newer)

**Step 1 — Install [Pixi](https://pixi.sh/latest/installation/).**

```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

**Step 2 — Enable Pixi.**

```bash
export PATH="$HOME/.pixi/bin:$PATH"
```

**Step 3 — Install the native Apple Silicon Mojara package.**

```bash
pixi global install 'mojara==1.2.7' -c https://mojara.kasua.ng/conda/ -c https://conda.modular.com/max/ -c conda-forge
```

**Step 4 — Verify that Mojara and Mojo are available.**

```bash
mojara doctor
```

Create an application using the steps in [Your first Mojara application](#create-your-first-application).

### macOS Intel — Docker Desktop

Intel Macs run Mojara using the official Linux x86-64 image. Install and start [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/).

**Step 1 — Pull Mojara for Intel.**

```bash
docker pull --platform linux/amd64 ghcr.io/mojara-framework/mojara:1.2.7
```

**Step 2 — Create a directory for the Mojara launcher.**

```bash
mkdir -p "$HOME/.local/bin"
```

**Step 3 — Install the launcher.**

```bash
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/macos/mojara-intel.sh -o "$HOME/.local/bin/mojara"
```

**Step 4 — Make it executable.**

```bash
chmod +x "$HOME/.local/bin/mojara"
```

**Step 5 — Add it to your terminal PATH.**

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that same export line to `~/.zshrc` to keep it available in future Terminal sessions.

**Step 6 — Check the installation.**

```bash
mojara doctor
```

**Step 7 — Create and run an application.** Follow [Your first Mojara application](#create-your-first-application).

The launcher keeps project files on your Mac and runs the Linux Mojo compiler in Docker. The application is accessible at `http://localhost:8000`.

**Processor requirement:** Mojo on Linux x86-64 requires an x86-64-v3 compatible CPU, including AVX2. Older Intel Macs may not meet this requirement.

### macOS Intel — without Docker (Lima VM)

[Lima](https://lima-vm.io/) runs Ubuntu in a lightweight virtual machine without Docker. Install [Homebrew](https://brew.sh/) first.

**Step 1 — Install Lima.**

```bash
brew install lima
```

**Step 2 — Create an Ubuntu VM.**

```bash
limactl start --name=mojara-linux template:ubuntu
```

**Step 3 — Enter Ubuntu.**

```bash
limactl shell mojara-linux
```

**Step 4 — Install prerequisites in Ubuntu.**

```bash
sudo apt update
```

```bash
sudo apt install -y build-essential curl ca-certificates
```

**Step 5 — Install Pixi in Ubuntu.**

```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

```bash
export PATH="$HOME/.pixi/bin:$PATH"
```

**Step 6 — Install Mojara and its development watcher.**

```bash
pixi global install 'mojara==1.2.7' -c https://mojara.kasua.ng/conda/ -c https://conda.modular.com/max/ -c conda-forge
```

```bash
pixi global install 'watchexec>=2.7,<3' -c conda-forge
```

**Step 7 — Create a project and enter its folder.**

```bash
mojara new hello-mojara
```

```bash
cd hello-mojara
```

**Step 8 — Run the application in the VM.**

```bash
MOJARA_HOST=0.0.0.0 mojara dev
```

Visit `http://localhost:8000` on the Mac. This runs the Linux compiler inside a VM, not a native Intel macOS compiler. The same x86-64-v3 processor requirement applies. [Full macOS guide](docs/INSTALL-MACOS.md).

## Install with Docker on any supported CPU

The public image is `ghcr.io/mojara-framework/mojara`, available for Linux AMD64 and ARM64. Docker selects the matching architecture automatically.

**Step 1 — Download the image.**

```bash
docker pull ghcr.io/mojara-framework/mojara:1.2.7
```

**Step 2 — Check its Mojara version.**

```bash
docker run --rm ghcr.io/mojara-framework/mojara:1.2.7 version
```

**Step 3 — Create a project in the current host folder.**

```bash
docker run --rm -v "$PWD:/workspace" ghcr.io/mojara-framework/mojara:1.2.7 new hello-mojara
```

**Step 4 — Enter the project folder.**

```bash
cd hello-mojara
```

**Step 5 — Start development with hot reload.**

```bash
docker run --rm -it -p 127.0.0.1:8000:8000 -v "$PWD:/workspace" ghcr.io/mojara-framework/mojara:1.2.7 dev
```

Open `http://localhost:8000`.

**Step 6 — Compile the project (in a separate terminal, or after stopping the dev server).**

```bash
docker run --rm -v "$PWD:/workspace" ghcr.io/mojara-framework/mojara:1.2.7 build
```

**Step 7 — Run the compiled project.**

```bash
docker run --rm -it -p 127.0.0.1:8000:8000 -v "$PWD:/workspace" ghcr.io/mojara-framework/mojara:1.2.7 start --local
```

The [Docker guide](docs/DOCKER.md) includes Docker Compose, deployment and architecture details.

## Create your first application

Use these commands after installing Mojara through Pixi, WSL2, or the Intel Mac Docker launcher.

**Step 1 — Create a project.**

```bash
mojara new hello-mojara
```

**Step 2 — Change into the new directory.**

```bash
cd hello-mojara
```

**Step 3 — Start development.**

```bash
mojara dev
```

Open `http://localhost:8000`. For a JSON API, use `mojara new hello-api --api`.

**Step 4 — Compile the app when ready.**

```bash
mojara build
```

**Step 5 — Start the compiled app.**

```bash
mojara start --local
```

The `new` command creates an application directly in the current directory; no project-level Pixi setup or framework source checkout is necessary. [Tutorial](https://mojara.kasua.ng/docs/tutorial.html) · [CLI reference](https://mojara.kasua.ng/docs/cli.html).

## Compile Mojara itself from GitHub

Use this section to compile the **actual framework source**, including Mojara's Mojo modules, command-line tool, and first-party C/C++ bridges. The independent upstream Mojo dependencies are pinned and checksum-verified.

### Linux x86-64, Linux ARM64, or Windows through WSL2

Run these commands in an Ubuntu terminal.

**Step 1 — Install native build tools.**

```bash
sudo apt update
```

```bash
sudo apt install -y git curl ca-certificates build-essential pkg-config python3 patch patchelf binutils
```

**Step 2 — Install Pixi.**

```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

```bash
export PATH="$HOME/.pixi/bin:$PATH"
```

**Step 3 — Clone the Mojara repository.**

```bash
git clone https://github.com/mojara-framework/mojara.git
```

```bash
cd mojara
```

**Step 4 — Install the framework's build dependencies.**

```bash
pixi install
```

**Step 5 — Retrieve and verify pinned upstream source.**

```bash
pixi run bash scripts/ci/bootstrap-source.sh
```

**Step 6 — Compile Mojara's native SDK.**

```bash
pixi run bash scripts/ci/build-source-sdk.sh
```

**Step 7 — Select your locally compiled SDK.**

```bash
export MOJARA_HOME="$PWD/build/full-integration/sdk"
```

```bash
export PATH="$MOJARA_HOME/bin:$PWD/.pixi/envs/default/bin:$PATH"
```

```bash
export LD_LIBRARY_PATH="$MOJARA_HOME/lib:$PWD/.pixi/envs/default/lib:${LD_LIBRARY_PATH:-}"
```

```bash
mojara doctor
```

### macOS Apple Silicon source build

**Step 1 — Install Apple's command-line compiler tools.**

```bash
xcode-select --install
```

**Step 2 — Install Pixi.**

```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

```bash
export PATH="$HOME/.pixi/bin:$PATH"
```

**Step 3 — Clone Mojara.**

```bash
git clone https://github.com/mojara-framework/mojara.git
```

```bash
cd mojara
```

**Step 4 — Install dependencies and retrieve upstream source.**

```bash
pixi install
```

```bash
pixi run bash scripts/ci/bootstrap-source.sh
```

**Step 5 — Compile the Apple Silicon SDK.**

```bash
pixi run bash scripts/ci/build-macos-sdk.sh
```

**Step 6 — Enable and verify the locally built SDK.**

```bash
export MOJARA_HOME="$PWD/build/full-integration/sdk"
```

```bash
export PATH="$MOJARA_HOME/bin:$PWD/.pixi/envs/default/bin:$PATH"
```

```bash
export DYLD_LIBRARY_PATH="$MOJARA_HOME/lib:$PWD/.pixi/envs/default/lib:${DYLD_LIBRARY_PATH:-}"
```

```bash
mojara doctor
```

All built files are in `build/full-integration/sdk/`. [Detailed source build guide](docs/BUILD-FROM-SOURCE.md).

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
