# Cross-platform build and test status

Mojara is published for Linux x86-64. Its first-party source is being prepared for other platforms. The three targets require **different degrees of testing**.

## Automated GitHub Actions checks

| Workflow | Target | Trigger | Test scope |
| --- | --- | --- | --- |
| [Mojara Linux portability CI](../.github/workflows/mojara-cross-platform.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Native Mojo CLI build and starter project generation |
| [Native bridge regressions](../.github/workflows/native-bridge-regressions.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | File serving, uploads, telemetry C API tests |
| [Linux connection pool and shutdown regressions](../.github/workflows/pool-regressions.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Bounded leases, concurrency, timeouts, reuse and shutdown |
| [Full Linux framework integration](../.github/workflows/full-linux-integration.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Source-built SDK, HTTP, sessions, uploads, WebSockets, concurrency, shutdown and real SQL |
| [Native Conda package fresh-install qualification](../.github/workflows/ci-package.yml) | Linux x86-64 + Linux ARM64 | Push, PR, manual | Package build, fresh Pixi install, native app, HTTP and dependency verification on a clean runner |
| [macOS Apple Silicon validation](../.github/workflows/mojara-macos-validation.yml) | macOS 15 Apple Silicon | **Manual** | Native CLI and starter project generation; experimental |

macOS validation is manual while GitHub-hosted macOS runners are frequently queued. You can run it from **Actions → macOS Apple Silicon validation (experimental) → Run workflow**. The Linux jobs are intentionally independent so a queued Mac runner does not falsely mark the Linux checks as failed.

## Actual platform support

| Target | CLI | Native regression tests | Full app | Production package |
| --- | --- | --- | --- | --- |
| Linux x86-64 | Verified | Verified | Verified for 1.2.5 on a local server | **Released (1.2.5)** |
| Linux ARM64 | Verified | Verified | HTTP, signed sessions, multipart uploads, WebSockets, concurrent traffic, shutdown and live SQL verified | Unpublished CI package passes clean installation |
| macOS Apple Silicon | Runner-dependent | Not verified | Not verified | Not released |
| Windows through WSL2 x86-64 | Existing Linux setup | Via Linux | Via Linux | Supported via Linux package |
| Native Windows | No native Mojo toolchain yet | Not verified | Not verified | Not released |

**Linux ARM64 is not a published production target yet.** The integration and clean-runner installation tests pass, but independent dependency provenance, complete native extension qualification, package-linking review and public-channel release checks remain. Follow the [release checklist](RELEASE-CHECKLIST.md) before advertising a new supported package.

## Native Mojo Windows

Modular announced in August 2026 that it is working with Microsoft's Windows team on native Windows support. Official system requirements still list Windows via WSL2. Follow [Windows notes](WINDOWS.md) for current details.
