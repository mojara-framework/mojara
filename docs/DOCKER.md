# Mojara Docker image

Mojara is distributed as a ready-to-use Linux Docker image for **x86-64 (amd64)** and **ARM64 (arm64)**. It includes the native Mojara CLI, Mojo compiler and the C/C++ linker needed to build applications. The Docker image installs the published Mojara package; it does not require cloning the framework's GitHub repository.

## Pull Mojara

```bash
docker pull ghcr.io/mojara-framework/mojara:1.2.9
docker run --rm ghcr.io/mojara-framework/mojara:1.2.9 version
docker run --rm ghcr.io/mojara-framework/mojara:1.2.9 doctor
```

`latest` is also published. For reproducible application builds, prefer the explicit release tag.

## Create an application

From the directory where you keep your projects:

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.9 \
  new hello-mojara

cd hello-mojara
```

Your application is created on the host filesystem, rather than being lost when the container exits.

## Develop and open the browser

```bash
docker run --rm -it \
  -p 127.0.0.1:8000:8000 \
  -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.9 \
  dev
```

Open [http://localhost:8000](http://localhost:8000). Source changes are read from the bind-mounted folder. The published image contains `watchexec` so that `mojara dev` can rebuild when your files change.

## Compile and run the application

Compile Mojo application source into a native binary:

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.9 \
  build
```

Start the previously compiled application:

```bash
docker run --rm -it \
  -p 127.0.0.1:8000:8000 \
  -v "$PWD:/workspace" \
  ghcr.io/mojara-framework/mojara:1.2.9 \
  start --local
```

## Docker Compose

Create a `compose.yaml` in an existing Mojara application directory:

```yaml
services:
  mojara:
    image: ghcr.io/mojara-framework/mojara:1.2.9
    working_dir: /workspace
    volumes:
      - .:/workspace
    ports:
      - "127.0.0.1:8000:8000"
    environment:
      MOJARA_HOST: "0.0.0.0"
      MOJARA_PORT: "8000"
    command: ["dev"]
```

Run `docker compose up` to start the development server. For a compiled deployment, run `mojara build` once and change `command` to `["start", "--local"]`. Configure your application's secrets and database connectivity using your normal environment and deployment tooling.

## Intel Mac and other platforms

- **Intel Macs:** Install Docker Desktop and run the Linux `amd64` image. The current folder is shared with the container and the browser uses your Mac's localhost. See [macOS installation](INSTALL-MACOS.md).
- **Apple Silicon:** Native Mojara installation is available; the Docker `arm64` image is an alternative.
- **Windows:** Use Docker Desktop with its WSL2 backend, or install Mojara directly inside WSL2 Ubuntu.
- **Linux:** Docker selects the matching `amd64` or `arm64` image automatically.

To explicitly select the Intel Mac/Linux x86-64 image, add `--platform linux/amd64` to `docker pull` or `docker run`.

Mojo's Linux x86-64 compiler requires an **x86-64-v3 compatible CPU** (Haswell-class or newer). Older Intel Mac processors without AVX2 and the other required features cannot execute this image. Docker does not bypass that hardware requirement.

## Image publishing and source builds

The automated [Docker release workflow](../.github/workflows/publish-docker.yml) builds and tests image variants on Linux x86-64 and ARM64, including the native Mojara compiler, file watcher, generated project and HTTP server. Verified images are published to the GitHub Container Registry under `ghcr.io/mojara-framework/mojara`.

To build the Docker image locally:

```bash
docker build --platform linux/amd64 \
  -t mojara:local \
  -f packaging/docker/Dockerfile .
```

To **compile the Mojara framework from the GitHub repository**, rather than installing a released Mojara package in Docker, follow [Build Mojara from source](BUILD-FROM-SOURCE.md).
