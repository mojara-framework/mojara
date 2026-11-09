# Changelog

All notable changes are recorded here. Dates are in UTC.

## 1.2.5 — 2026-11-09

- Fixed the Conda/Pixi global launcher to resolve its real installation prefix when invoked through a symlink.
- Made the global installation usable from any directory without a project-level Pixi workspace.
- Verified project creation, Mojo application compilation and the HTTP health route on Linux x86-64.
- Published the v1.2.5 Conda package and updated the installation/CLI documentation.

## Linux ARM64 source-build qualification — 2026-11-09

- GitHub Actions built all core first-party Mojo modules and native C/C++ shared libraries directly on Linux ARM64 and x86-64.
- Both architectures compiled and served a generated Mojara application with working HTTP JSON, HTML templates and static files.
- Both architectures passed live Mojo PostgreSQL and MariaDB prepared-query and transaction-control smoke checks using temporary CI database services.
- This does **not** yet constitute a stable ARM64 package release; WebSockets, extended auth/uploads, load/shutdown and fresh installation tests remain.

## Source repository establishment — 2026-11-09

- Imported first-party framework, CLI and native bridge source from the v1.2.5 SDK.
- Established cross-platform CLI checks for Linux x86-64, Linux ARM64 and Apple Silicon macOS.
- Added automated Linux x86-64 / ARM64 native bridge regression tests.
- Added source documentation, contribution policies and release gates.

The repository work is **not** a new Mojara binary release. Native Windows, Linux ARM64 and macOS are not yet production-supported.
