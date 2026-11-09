# Changelog

All notable changes are recorded here. Dates are in UTC.

## 1.2.5 — 2026-11-09

- Fixed the Conda/Pixi global launcher to resolve its real installation prefix when invoked through a symlink.
- Made the global installation usable from any directory without a project-level Pixi workspace.
- Verified project creation, Mojo application compilation and the HTTP health route on Linux x86-64.
- Published the v1.2.5 Conda package and updated the installation/CLI documentation.

## Source repository establishment — 2026-11-09

- Imported first-party framework, CLI and native bridge source from the v1.2.5 SDK.
- Established cross-platform CLI checks for Linux x86-64, Linux ARM64 and Apple Silicon macOS.
- Added automated Linux x86-64 / ARM64 native bridge regression tests.
- Added source documentation, contribution policies and release gates.

The repository work is **not** a new Mojara binary release. Native Windows, Linux ARM64 and macOS are not yet production-supported.
