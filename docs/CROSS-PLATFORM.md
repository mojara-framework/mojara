# Cross-platform build and test status

Mojara publishes native Conda packages for Linux x86-64, Linux ARM64 and macOS Apple Silicon. Windows uses WSL2 Ubuntu; Intel Macs can run Mojara through Docker or a Linux VM.

## Automated GitHub Actions checks

| Workflow | Target | Trigger | Test scope |
| --- | --- | --- | --- |
| [Mojara Linux portability CI](../.github/workflows/mojara-cross-platform.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Native Mojo CLI build and starter project generation |
| [Native bridge regressions](../.github/workflows/native-bridge-regressions.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | File serving, uploads, telemetry C API tests |
| [Linux connection pool and shutdown regressions](../.github/workflows/pool-regressions.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Bounded leases, concurrency, timeouts, reuse and shutdown |
| [Full Linux framework integration](../.github/workflows/full-linux-integration.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Source-built SDK, HTTP, sessions, uploads, WebSockets, concurrency, shutdown and real SQL |
| [Native Conda package fresh-install qualification](../.github/workflows/ci-package.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Package build, fresh Pixi install, native app, HTTP and dependency verification on a clean runner |
| [Native Linux release qualification](../.github/workflows/release-linux.yml) | Linux x86-64 + Linux ARM64 | PR, qualified main CI, manual | Public-ready package build, independent fresh installation, live SQL and gated GitHub publication |
| [macOS Apple Silicon qualification](../.github/workflows/mojara-macos-26-validation.yml) | macOS 26 Apple Silicon | Main, PR, manual | Mach-O native bridges, full Mojo framework, generated application, HTTP, Conda package and independent clean installation |
| [macOS 15 compatibility check](../.github/workflows/mojara-macos-validation.yml) | macOS 15 Apple Silicon | Manual | Additional compatibility validation |

Apple Silicon package qualification runs on macOS 26 independently of the Linux CI matrix. The macOS 15 compatibility check is available manually.

## Platform support

| Platform | Status |
| --- | --- |
| Linux x86-64 | **Supported** |
| Linux ARM64 (AArch64) | **Supported** |
| Windows 10/11 with WSL2 Ubuntu (x86-64) | **Supported** |
| macOS Apple Silicon | **Supported** |
| macOS Intel through Docker (Linux x86-64) | **Supported** |
| macOS Intel through a Linux virtual machine | Linux VM installation available |
| Native Windows | Not yet supported |

For release downloads, see [Mojara 1.2.8](https://github.com/mojara-framework/mojara/releases/tag/v1.2.8). The Mojara Conda channel serves Linux x86-64, Linux ARM64 and macOS Apple Silicon.

## Native Mojo Windows

Modular announced in August 2026 that it is working with Microsoft's Windows team on native Windows support. Official system requirements still list Windows via WSL2. Follow [Windows notes](WINDOWS.md) for current details.
