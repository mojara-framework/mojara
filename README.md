# Mojara 🔥

**Native web development with Mojo.**

Mojara is an open-source, Mojo-first web framework for routing, HTTP APIs, templates, sessions, authentication, uploads, real-time applications, and relational databases. Applications are written in Mojo; performance-sensitive adapters use native C bridges.

[Documentation](https://mojara.kasua.ng/docs/) · [Complete Mojara API reference](docs/API-REFERENCE.md) · [Installation](https://mojara.kasua.ng/docs/install.html) · [CLI guide](https://mojara.kasua.ng/docs/cli.html) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

[![Native bridge regressions](https://github.com/mojara-framework/mojara/actions/workflows/native-bridge-regressions.yml/badge.svg)](https://github.com/mojara-framework/mojara/actions/workflows/native-bridge-regressions.yml)
[![Cross-platform CLI checks](https://github.com/mojara-framework/mojara/actions/workflows/mojara-cross-platform.yml/badge.svg)](https://github.com/mojara-framework/mojara/actions/workflows/mojara-cross-platform.yml)
[![Full Linux integration](https://github.com/mojara-framework/mojara/actions/workflows/full-linux-integration.yml/badge.svg)](https://github.com/mojara-framework/mojara/actions/workflows/full-linux-integration.yml)

## Install

**Official Linux x86-64 and ARM64 packages:** [Mojara 1.2.6 release](https://github.com/mojara-framework/mojara/releases/tag/v1.2.6). Install using Pixi and the package matching your CPU. You do not need to clone this repository.

### Linux ARM64

```bash
curl -fLO https://github.com/mojara-framework/mojara/releases/download/v1.2.6/mojara-1.2.6-he8cfe8b_0.conda
pixi global install --path ./mojara-1.2.6-he8cfe8b_0.conda \
  -c https://conda.modular.com/max/ -c conda-forge
```

### Linux x86-64 (including Windows WSL2)

```bash
curl -fLO https://github.com/mojara-framework/mojara/releases/download/v1.2.6/mojara-1.2.6-hb0f4dca_0.conda
pixi global install --path ./mojara-1.2.6-hb0f4dca_0.conda \
  -c https://conda.modular.com/max/ -c conda-forge
```

The [SHA256SUMS](https://github.com/mojara-framework/mojara/releases/download/v1.2.6/SHA256SUMS) file provides checksums for both binaries. The separately hosted `mojara.kasua.ng` Conda channel is not yet updated with the ARM64 package, so install it using the GitHub Release until that channel is indexed.

Then use Mojara anywhere:

```bash
mojara version
mojara doctor
mojara new hello-mojara
cd hello-mojara
mojara dev
```

The `new` command creates an application directory directly, without an additional nested project or a project-level `pixi.toml`.

## What it includes

- Native Mojo CLI: project generation, development watching, compilation, local startup, diagnostics and Linux deployment.
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
| macOS Apple Silicon | Experimental |
| Windows native | Not yet supported |

See [cross-platform progress](docs/CROSS-PLATFORM.md) and [Windows approach](docs/WINDOWS.md). CI badges are indicators of the named tests, **not** broad production certification.

## Repository layout

```text
source/
  cli/                   Native Mojo command-line tool
  mojara/                First-party Mojo framework modules
  native/                First-party C bridges
tests/native/             Executable native regression tests
scripts/                  Source-development build/test commands
packaging/conda/          Source-native multi-architecture Conda release recipe
docs/                     Tutorials, complete Mojara API reference and release process
.github/workflows/        Platform matrix and native regression CI
```

**Source build note:** The complete first-party Mojo library, CLI and native C bridge code are in this repository. Third-party Mojo modules are currently recovered from a checksum-pinned source bundle; independently pinned upstream revisions and complete extension provenance remain release-hardening work.

## Development and community

Start with [Contributing](CONTRIBUTING.md), [Support](SUPPORT.md), and the [Roadmap](docs/ROADMAP.md). Report reproducible problems through [Issues](https://github.com/mojara-framework/mojara/issues). For vulnerabilities, follow [Security](SECURITY.md).

Before resetting Windows/WSL2, follow the [safe WSL backup and Mojara reinstall procedure](docs/WSL-RESET.md).

Released under the [MIT License](LICENSE). Third-party components retain their own licenses; see [third-party notices](docs/THIRD_PARTY_LICENSES.md).
