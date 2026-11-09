# Continuous integration

Mojara keeps portable CLI checks, native C regressions and platform experiments separate so each result is accurate.

## Required Linux checks

1. **Mojara Linux portability CI** compiles the Mojo CLI and confirms that `mojara new` creates a normal application directory on Linux x86-64 and ARM64.
2. **Native bridge regressions** compiles and runs C tests for static files, safe multipart uploads and concurrent telemetry on both Linux architectures.
3. **Linux connection pool and shutdown regressions** exercises bounded leases, concurrency, timeouts, reuse and shutdown on x86-64 and ARM64.
4. **Full Linux framework integration** verifies the pinned third-party source bundle, builds native libraries and the Mojo framework on both CPUs, then tests HTTP routes, static files, real PostgreSQL and MariaDB transactions, signed sessions, form parsing, authenticated multipart uploads, WebSocket protocol handling, concurrent HTTP requests and bounded server shutdown.
5. **Native Conda package fresh-install qualification** creates separate unpublished packages for x86-64 and ARM64, verifies `mojara doctor`, compiles and serves a newly generated application, and repeats installation on clean runners without C development headers. It also checks installed ELF dependency resolution.

These workflows run on relevant pushes and pull requests. They can also be run from the Actions tab without a local installation.

## Public Conda distribution

The [public channel install workflow](../.github/workflows/channel-install.yml) checks that Mojara installs by package name and serves HTTP on fresh Linux x86-64 and ARM64 runners.

## Optional macOS checks

**macOS Apple Silicon validation (experimental)** runs only when requested manually. GitHub may queue the job until an Apple Silicon runner becomes available. A job in a queued state has not tested the project and must not be recorded as a compilation failure.

## Release qualification gaps

The release workflow builds native packages for both Linux CPU architectures, then independently installs them and verifies native links, real PostgreSQL and MariaDB prepared SQL, and generated application HTTP startup. Outstanding work covers independently pinned upstream source revisions, the full transaction-pool extension, deeper SSE/deployment coverage, platform-specific ABI diagnostics and native macOS validation.

For the source-level declarations available to application developers, see the [Mojara API reference](API-REFERENCE.md).

## Publishing

The [native Linux release workflow](../.github/workflows/release-linux.yml) publishes verified packages and their SHA-256 checksums to [GitHub Releases](https://github.com/mojara-framework/mojara/releases). The separately hosted custom Conda channel requires an independent update of its packages and `repodata.json` indexes.
