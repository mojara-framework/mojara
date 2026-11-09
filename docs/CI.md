# Continuous integration

Mojara keeps portable CLI checks, native C regressions and platform experiments separate so each result is accurate.

## Required Linux checks

1. **Mojara Linux portability CI** compiles the Mojo CLI and confirms that `mojara new` creates a normal application directory on Linux x86-64 and ARM64.
2. **Native bridge regressions** compiles and runs C tests for static files, safe multipart uploads and concurrent telemetry on both Linux architectures.

Both run on relevant pushes and pull requests. They can also be run from the Actions tab without a local installation.

## Optional macOS checks

**macOS Apple Silicon validation (experimental)** runs only when requested manually. GitHub may queue the job until an Apple Silicon runner becomes available. A job in a queued state has not tested the project and must not be recorded as a compilation failure.

## Full application compatibility

Not yet part of these CI gates: building all third-party libraries, precompiling the Mojara framework, compiling a generated app, HTTP/WebSocket requests, MySQL/PostgreSQL integration, load and shutdown tests on ARM64/macOS. These must be added before issuing platform packages.

## Publishing

No workflow in this repository currently publishes to the official Conda channel or creates a stable release automatically. Publication needs independent approval after the [release checklist](RELEASE-CHECKLIST.md) passes.
