# Changelog

All notable changes are recorded here. Dates are in UTC.

## 1.2.8 - 2026-11-10

- Improved `mojara dev` to reuse the compiled Mojo executable on HTML, CSS, JavaScript and JSON changes; Mojo-source changes still trigger compilation.
- Restored the native PostgreSQL/MySQL transaction-pool implementation and Mojo bridge to the public source tree and compiled both libraries as part of native Linux and Apple Silicon builds.
- Added thread-affinity, rollback, timeout, offline error-path and live database transaction-pool regression checks.
- Added documentation synchronization for the official Mojara website, with change detection and validation.
- Continued native library ABI and dependency auditing on packaged releases.

## 1.2.7 - 2026-11-09

- Added native macOS Apple Silicon builds of the Mojara Mojo framework, command-line interface, and C/C++ bridges.
- Implemented macOS dynamic-library loading and compatible native randomness and connection-pool primitives.
- Built a generated Mojara application and verified its HTTP server on Apple Silicon.
- Added a native `osx-arm64` Conda package with independent fresh-install and application startup qualification.
- Released updated Linux x86-64 and ARM64 packages from the same reviewed source revision, retaining their database and HTTP integration checks.

## 1.2.6 - 2026-11-09

- Published native Linux x86-64 and ARM64 Conda packages with SHA-256 checksums as verified GitHub Release assets.
- Compiled the Mojo CLI for baseline host CPUs to avoid runner-specific instruction requirements.
- Linked native database bridges against declared Conda dependencies and verified relocatable runtime library lookup.
- Added independent installed-package PostgreSQL and MariaDB prepared-query and transaction integration tests.
- Validated signed sessions, uploads, WebSockets, concurrent requests and shutdown on both Linux architectures.
- Added gated release automation and public API reference documentation.

## 1.2.5 - 2026-11-09

- Fixed the Conda/Pixi global launcher to resolve its real installation prefix when invoked through a symlink.
- Made the global installation usable from any directory without a project-level Pixi workspace.
- Verified project creation, Mojo application compilation and the HTTP health route on Linux x86-64.
- Published the v1.2.5 Conda package and updated the installation/CLI documentation.

## Linux ARM64 source-build qualification - 2026-11-09

- GitHub Actions built all core first-party Mojo modules and native C/C++ shared libraries directly on Linux ARM64 and x86-64.
- Both architectures compiled and served a generated Mojara application with working HTTP JSON, HTML templates and static files.
- Both architectures passed live Mojo PostgreSQL and MariaDB prepared-query and transaction-control smoke checks using temporary CI database services.
- This does **not** yet constitute a stable ARM64 package release; WebSockets, extended auth/uploads, load/shutdown and fresh installation tests remain.

## Source repository establishment - 2026-11-09

- Imported first-party framework, CLI and native bridge source from the v1.2.5 SDK.
- Established cross-platform CLI checks for Linux x86-64, Linux ARM64 and Apple Silicon macOS.
- Added automated Linux x86-64 / ARM64 native bridge regression tests.
- Added source documentation, contribution policies and release gates.

Native Windows and Intel macOS remain unreleased.
