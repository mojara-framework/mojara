# Continuous integration

Mojara keeps portable CLI checks, native C regressions and platform experiments separate so each result is accurate.

## Required Linux checks

1. **Mojara Linux portability CI** compiles the Mojo CLI and confirms that `mojara new` creates a normal application directory on Linux x86-64 and ARM64.
2. **Native bridge regressions** compiles and runs C tests for static files, safe multipart uploads and concurrent telemetry on both Linux architectures.
3. **Linux connection pool and shutdown regressions** exercises bounded leases, concurrency, timeouts, reuse and shutdown on x86-64 and ARM64.
4. **Full Linux framework integration** verifies the pinned third-party source bundle, builds native libraries and the Mojo framework on both CPUs, then tests HTTP routes, static files, real PostgreSQL and MariaDB transactions, signed sessions, form parsing, authenticated multipart uploads, WebSocket protocol handling, concurrent HTTP requests and bounded server shutdown.
5. **Native Conda package fresh-install qualification** creates separate unpublished packages for x86-64 and ARM64, verifies `mojara doctor`, compiles and serves a newly generated application, and repeats installation on clean runners without C development headers. It also checks installed ELF dependency resolution.

Both run on relevant pushes and pull requests. They can also be run from the Actions tab without a local installation.

## Optional macOS checks

**macOS Apple Silicon validation (experimental)** runs only when requested manually. GitHub may queue the job until an Apple Silicon runner becomes available. A job in a queued state has not tested the project and must not be recorded as a compilation failure.

## Release qualification gaps

The Linux application tests and isolated package tests cover both CPU architectures. The source bootstrap still relies on the SHA-256-pinned third-party module bundle rather than independently pinned upstream source revisions. The complete transaction-pool extension, deeper SSE/load/deployment coverage, package relocation diagnostics and macOS native SDK validation remain separate release gates. Passing CI candidate tests is not the same as publishing or certifying a stable ARM64 package.

For the source-level declarations available to application developers, see the [Mojara API reference](API-REFERENCE.md).

## Publishing

No workflow in this repository currently publishes to the official Conda channel or creates a stable release automatically. Publication needs independent approval after the [release checklist](RELEASE-CHECKLIST.md) passes.
