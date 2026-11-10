# Contributing to Mojara

Thank you for contributing to Mojara. This is the official framework source repository, not a collection of independent experiments.

## Before opening a pull request

- Search existing issues and pull requests, then discuss large API changes in an issue.
- Keep changes focused. Include a regression test when fixing a bug.
- Do not commit passwords, credentials, generated binaries, `.pixi/`, compiled `.mojoc` files or package caches.
- Do not claim a new operating system is supported merely because the CLI compiles.
- Preserve the existing MIT license and the notices for third-party dependencies.

## Local development

To compile Mojara itself, follow the complete [build-from-source guide](docs/BUILD-FROM-SOURCE.md), available for Linux x86-64, Linux ARM64, and macOS Apple Silicon. The build uses Pixi for Mojo 1.2.0 and all native dependencies, independently pinned upstream source archives, and the first-party framework and CLI.

The ordinary user installation does **not** require cloning the repository or building the framework. Users can install with Pixi or run the [multiarchitecture Docker image](docs/DOCKER.md).

## Pull requests

Explain **what changed**, **why**, **which platforms**, **which tests ran**, and any **compatibility or security implications**. For new APIs, supply an example. For native C code, preserve explicit error handling, bounded buffers and FFI contracts.

The maintainers review PRs against the platform status and release checklist. CI must pass on the affected platforms before merging; every platform is tested separately.

## Reporting

- Bugs and feature requests: [GitHub Issues](https://github.com/mojara-framework/mojara/issues).
- Potential security vulnerabilities: follow [SECURITY.md](SECURITY.md), rather than posting an exploit publicly.
- Installation and end-user usage: [Mojara documentation](https://mojara.kasua.ng/docs/install.html).
