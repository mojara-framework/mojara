# Mojara 🔥

**Native web development with Mojo.**

Mojara is an open-source, Mojo-first web framework for routing, HTTP APIs, templates, sessions, authentication, uploads, real-time applications, and relational databases. Applications are written in Mojo; performance-sensitive adapters use native C bridges.

[Documentation](https://mojara.kasua.ng/docs/) · [Complete Mojara API reference](docs/API-REFERENCE.md) · [Installation](https://mojara.kasua.ng/docs/install.html) · [Docker](docs/DOCKER.md) · [Build from source](docs/BUILD-FROM-SOURCE.md) · [CLI guide](https://mojara.kasua.ng/docs/cli.html) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

## Install

Install Mojara with Pixi on Linux x86-64, Linux ARM64, macOS Apple Silicon, or Windows with WSL2 Ubuntu. Intel Macs run Mojara through Docker Desktop using the supported Linux x86-64 package. No source checkout is required.

```bash
pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
```

Then use Mojara anywhere:

```bash
mojara version
mojara doctor
mojara new hello-mojara
cd hello-mojara
mojara dev
```

The `new` command creates an application directory directly, without an additional nested project or a project-level `pixi.toml`.

## Docker

Mojara is also available as a ready-to-use Docker image on Linux x86-64 and ARM64:

```bash
docker pull ghcr.io/mojara-framework/mojara:1.2.7
docker run --rm ghcr.io/mojara-framework/mojara:1.2.7 version
```

The container includes Mojara, the Mojo compiler and build tools. You can generate, compile and run applications with bind-mounted project folders. See the [Docker installation and Compose guide](docs/DOCKER.md).

## Compile the framework from GitHub

Developers can build the full first-party Mojo framework and native CLI from the repository with the independently pinned upstream sources. Follow [Build Mojara from source](docs/BUILD-FROM-SOURCE.md). Normal users should use the published package or Docker image; cloning is only for contributing or building the framework itself.

## What it includes

- Native Mojo CLI: project generation, development watching, compilation, local startup, diagnostics and deployment tooling.
- HTTP routing, JSON responses, templates, static files and multipart uploads.
- Sessions, cookies, authentication and security helpers.
- MySQL, PostgreSQL and SQLite interfaces; migrations and ORM helpers.
- Async database jobs, connection pools, telemetry and lifecycle controls.
- Flare-based network stack for HTTP, WebSockets and streaming.

See [Architecture](docs/ARCHITECTURE.md) for component boundaries, [verified source provenance](docs/SOURCE-PROVENANCE.md), and third-party dependencies.

## Platform status

| Platform | Support |
| --- | --- |
| Linux x86-64 | **Supported** |
| Linux ARM64 (AArch64) | **Supported** |
| Windows 10/11 with WSL2 Ubuntu (x86-64) | **Supported** |
| macOS Apple Silicon | **Supported** |
| macOS Intel through Docker / Linux VM (x86-64) | **Supported** |
| Windows native | Not yet supported |

See [macOS installation](docs/INSTALL-MACOS.md) and [Windows setup](docs/WINDOWS.md) for platform-specific guidance.

## Repository layout

```text
source/
  cli/                   Native Mojo command-line tool
  mojara/                First-party Mojo framework modules
  native/                First-party C bridges
tests/native/             Executable native regression tests
scripts/                  Source-development build/test commands
packaging/conda/          Source-native multi-architecture Conda release recipe
packaging/docker/         Multiarchitecture Mojara Docker image
docs/                     Tutorials, complete Mojara API reference and release process
.github/workflows/        Platform matrix and native regression CI
```

## Development and community

Start with [Contributing](CONTRIBUTING.md), [Support](SUPPORT.md), and the [Roadmap](docs/ROADMAP.md). Report reproducible problems through [Issues](https://github.com/mojara-framework/mojara/issues). For vulnerabilities, follow [Security](SECURITY.md).

Released under the [MIT License](LICENSE). Third-party components retain their own licenses; see [third-party notices](docs/THIRD_PARTY_LICENSES.md).
