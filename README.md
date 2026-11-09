# Mojara 🔥

**Native web development with Mojo.**

Mojara is an open-source, Mojo-first web framework for routing, HTTP APIs, templates, sessions, authentication, uploads, real-time applications, and relational databases. Applications are written in Mojo; performance-sensitive adapters use native C bridges.

[Documentation](https://mojara.kasua.ng/docs/) · [Installation](https://mojara.kasua.ng/docs/install.html) · [CLI guide](https://mojara.kasua.ng/docs/cli.html) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

[![Native bridge regressions](https://github.com/mojara-framework/mojara/actions/workflows/native-bridge-regressions.yml/badge.svg)](https://github.com/mojara-framework/mojara/actions/workflows/native-bridge-regressions.yml)
[![Cross-platform CLI checks](https://github.com/mojara-framework/mojara/actions/workflows/mojara-cross-platform.yml/badge.svg)](https://github.com/mojara-framework/mojara/actions/workflows/mojara-cross-platform.yml)

## Install

**Supported release: Linux x86-64 and Windows through WSL2.** Developers install Mojara globally, not by cloning this source repository or creating a Pixi workspace for every application.

```bash
pixi global install "mojara==1.2.5" \
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

## What it includes

- Native Mojo CLI: project generation, development watching, compilation, local startup, diagnostics and Linux deployment.
- HTTP routing, JSON responses, templates, static files and multipart uploads.
- Sessions, cookies, authentication and security helpers.
- MySQL, PostgreSQL and SQLite interfaces; migrations and ORM helpers.
- Async database jobs, connection pools, telemetry and lifecycle controls.
- Flare-based network stack for HTTP, WebSockets and streaming.

See [Architecture](docs/ARCHITECTURE.md) for component boundaries, [verified source provenance](docs/SOURCE-PROVENANCE.md), and third-party dependencies.

## Platform status

| Target | Current state |
| --- | --- |
| Linux x86-64 | **Supported**, Mojara 1.2.5 |
| Windows 10/11 with WSL2 Ubuntu | **Supported** via Linux x86-64 |
| Linux ARM64 | Experimental: CLI/project generation passed CI; full framework not certified |
| macOS Apple Silicon | Experimental: CI target exists, full framework not certified |
| Windows native | Not yet available; requires native Mojo compiler/runtime and Windows adapters |

See [cross-platform progress](docs/CROSS-PLATFORM.md) and [Windows approach](docs/WINDOWS.md). CI badges are indicators of the named tests, **not** broad production certification.

## Repository layout

```text
source/
  cli/                   Native Mojo command-line tool
  mojara/                First-party Mojo framework modules
  native/                First-party C bridges
tests/native/             Executable native regression tests
scripts/                  Source-development build/test commands
packaging/conda/          Conda recipe from the 1.2.5 release
docs/                     Architecture, contributing and release process
.github/workflows/        Platform matrix and native regression CI
```

**Source build note:** The first-party code is checked in from the published Mojara v1.2.5 SDK. A fully independent rebuild still needs pinned, source-buildable third-party dependencies (Flare, JSON and others), the transaction-pool extension and architecture-specific packaging. We track these as explicit release gates rather than presenting a CLI-only build as the full framework.

## Development and community

Start with [Contributing](CONTRIBUTING.md), [Support](SUPPORT.md), and the [Roadmap](docs/ROADMAP.md). Report reproducible problems through [Issues](https://github.com/mojara-framework/mojara/issues). For vulnerabilities, follow [Security](SECURITY.md).

Before resetting Windows/WSL2, follow the [safe WSL backup and Mojara reinstall procedure](docs/WSL-RESET.md).

Released under the [MIT License](LICENSE). Third-party components retain their own licenses; see [third-party notices](docs/THIRD_PARTY_LICENSES.md).
