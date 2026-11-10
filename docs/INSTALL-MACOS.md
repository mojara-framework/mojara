# Install Mojara on macOS

Mojara supports Apple Silicon natively and Intel Macs through Docker's Linux x86-64 environment.

## Apple Silicon (M1-M5)

Install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/). Mojara 1.2.9 runs on Apple Silicon through the official Linux ARM64 image.

```bash
docker pull --platform linux/arm64 ghcr.io/mojara-framework/mojara:1.2.9
docker run --rm --platform linux/arm64 ghcr.io/mojara-framework/mojara:1.2.9 version
```

To create a project in your current folder:

```bash
docker run --rm --platform linux/arm64 -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.9 new hello-mojara
```

Then use the [Docker development commands](DOCKER.md) for running and building applications. Native Apple Silicon release binaries are distributed once the Apple Silicon build completes.

## Intel Mac (Docker Desktop)

Install [Docker Desktop for Mac with Intel chip](https://docs.docker.com/desktop/setup/install/mac-install/) and start Docker Desktop. Mojara and the Mojo compiler run inside a Linux x86-64 container; the application files remain in your Mac folder.

Pull the official Mojara Docker image:

```bash
docker pull --platform linux/amd64 ghcr.io/mojara-framework/mojara:1.2.9
```

The image includes Mojara, Mojo, the native linker and a development file watcher. You do not need to clone the repository. For local image builds, see the [Docker guide](DOCKER.md).

Install the Mojara command launcher:

```bash
mkdir -p "$HOME/.local/bin"
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/macos/mojara-intel.sh \
  -o "$HOME/.local/bin/mojara"
chmod +x "$HOME/.local/bin/mojara"
export PATH="$HOME/.local/bin:$PATH"
```

To keep that `PATH` configuration for future Terminal sessions, add the export line to `~/.zshrc`.

Create and run a project:

```bash
mojara version
mojara doctor
mojara new hello-mojara
cd hello-mojara
mojara dev
```

Open [http://localhost:8000](http://localhost:8000) on your Mac. The launcher mounts the current directory at `/workspace`, exposes the development server only on your Mac's loopback interface, and starts an x86-64 Linux container for each command.

You can also use `mojara build` and `mojara start --local` from the project directory. To change the browser-facing host port, set `MOJARA_DOCKER_PORT`, for example `MOJARA_DOCKER_PORT=8080 mojara dev`.

**Requirements:** an Intel Mac capable of running Docker Desktop for Mac; a processor compatible with Mojo's Linux x86-64-v3 CPU target. The container uses the official Mojara Linux x86-64 package and does not install or require a native macOS Intel Mojo compiler.

## Intel Mac without Docker: Lima Linux VM

If you prefer not to install Docker, use [Lima](https://lima-vm.io/) to run Mojara in an Ubuntu Linux virtual machine on the Intel Mac. Lima provides shared host folders and automatic localhost port forwarding, much like Windows WSL2.

From macOS Terminal:

```bash
brew install lima
limactl start --name=mojara-linux template:ubuntu
limactl shell mojara-linux
```

Inside the Ubuntu shell, install the compiler's system linker and Mojara:

```bash
sudo apt update
sudo apt install -y build-essential curl ca-certificates
curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"

curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/install.sh | bash

pixi global install 'watchexec>=2.7,<3' -c conda-forge

mojara doctor
mojara new hello-mojara
cd hello-mojara
MOJARA_HOST=0.0.0.0 mojara dev
```

Visit `http://localhost:8000` from macOS. You can also open and edit your Mojara source through Lima's shared home directory.

This method **does not use Docker**. The compiler still runs on Linux x86-64 inside the virtual machine rather than natively on macOS Intel. It requires an x86-64-v3 capable CPU and enough RAM for Mojo development.

## Mojara release

The [Mojara 1.2.9 release](https://github.com/mojara-framework/mojara/releases/tag/v1.2.9) provides verified Linux x86-64 and ARM64 packages. Both Intel and Apple Silicon Macs can use the official Docker images.
