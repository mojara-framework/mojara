# Cross-platform development and verification

This repository starts with the Mojo CLI portability smoke checks.

## GitHub Actions

Open **Actions → Mojara cross-platform CI** in this repository, then choose **Run workflow**. Pushes affecting the CLI, scripts, Pixi manifest or workflow also start the checks automatically.

| Target | GitHub runner | Current gate |
|---|---|---|
| Linux x86-64 | `ubuntu-24.04` | Native CLI compilation and project creation |
| Linux ARM64 | `ubuntu-24.04-arm` | Native CLI compilation and project creation |
| macOS Apple Silicon | `macos-15` | Native CLI compilation and project creation |

Passing these gates does not imply that Mojara's native HTTP server, WebSockets, MySQL, PostgreSQL, uploads, database transactions, concurrency and shutdown have passed on that target.

## Required release gates

1. Build the full framework against Mojo 1.2.0 and platform-appropriate Flare, JSON and native dependencies.
2. Recompile every C bridge for the host architecture; do not reuse Linux x86-64 shared objects on ARM64 or macOS.
3. Validate native HTTP serving, templates, uploads, WebSockets, MySQL/PostgreSQL, transactions and concurrent requests.
4. Validate stop/restart, development watcher, and CLI packaging on each native host.
5. Package in `linux-64`, `linux-aarch64` and `osx-arm64` Conda subdirectories, and verify a **fresh `pixi global install`** per platform.
6. Only then label ARM64/macOS supported.

Windows native is blocked on availability of a compatible official Mojo compiler/runtime; WSL2 remains the supported Windows path.

**No CI job in this initial workflow publishes packages or updates the public release channel.**
