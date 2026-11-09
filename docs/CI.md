# Continuous integration

Mojara keeps portable CLI checks, native C regressions and platform experiments separate so each result is accurate.

## Required Linux checks

1. **Mojara Linux portability CI** compiles the Mojo CLI and confirms that `mojara new` creates a normal application directory on Linux x86-64 and ARM64.
2. **Native bridge regressions** compiles and runs C tests for static files, safe multipart uploads and concurrent telemetry on both Linux architectures.
3. **Full Linux framework integration** checksum-verifies the published v1.2.5 dependency-source archive, rebuilds the platform-native C/C++ libraries, precompiles first-party Mojo source, builds and runs a generated HTTP app and checks live PostgreSQL/MariaDB prepared queries and transaction controls on real Linux x86-64 and ARM64 runners.

Both run on relevant pushes and pull requests. They can also be run from the Actions tab without a local installation.

## Optional macOS checks

**macOS Apple Silicon validation (experimental)** runs only when requested manually. GitHub may queue the job until an Apple Silicon runner becomes available. A job in a queued state has not tested the project and must not be recorded as a compilation failure.

## Full application compatibility

Not yet covered by the full integration workflow: HTTP WebSocket upgrades, end-to-end sessions/authentication and HTTP uploads, stress/load tests, graceful shutdown, full transaction-pool extension build, ARM64 Conda packaging and fresh installation, and macOS native SDK tests. The dependency bootstrap uses SHA-256-verified source from the published Linux x86-64 SDK, not independently pinned upstream repositories; native libraries and the application are rebuilt on each runner. These remaining gates must pass before publishing ARM64/macOS packages.

## Publishing

No workflow in this repository currently publishes to the official Conda channel or creates a stable release automatically. Publication needs independent approval after the [release checklist](RELEASE-CHECKLIST.md) passes.
