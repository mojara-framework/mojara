# Install Mojara on macOS

Mojara supports Apple Silicon natively and Intel Macs through Docker's Linux x86-64 environment.

## Apple Silicon (M1–M5)

Install [Pixi](https://pixi.sh/latest/installation/), then run:

```bash
pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge

mojara new hello-mojara
cd hello-mojara
mojara dev
```

## Intel Mac (Docker Desktop)

Install [Docker Desktop for Mac with Intel chip](https://docs.docker.com/desktop/setup/install/mac-install/) and start Docker Desktop. Mojara and the Mojo compiler run inside a Linux x86-64 container; the application files remain in your Mac folder.

Build the Mojara image without cloning the source repository:

```bash
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/packaging/docker/Dockerfile \
  | docker build --platform linux/amd64 -t mojara-intel -
```

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

## Mojara release

The [Mojara 1.2.7 release](https://github.com/mojara-framework/mojara/releases/tag/v1.2.7) provides native Conda packages for Linux x86-64, Linux ARM64 and Apple Silicon. Intel Macs run the Linux x86-64 package using the Docker setup above.
