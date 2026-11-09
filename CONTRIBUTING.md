# Contributing to Mojara

Thank you for contributing to Mojara. This is the official framework source repository, not a collection of independent experiments.

## Before opening a pull request

- Search existing issues and pull requests, then discuss large API changes in an issue.
- Keep changes focused. Include a regression test when fixing a bug.
- Do not commit passwords, credentials, generated binaries, `.pixi/`, compiled `.mojoc` files or package caches.
- Do not claim a new operating system is supported merely because the CLI compiles.
- Preserve the existing MIT license and the notices for third-party dependencies.

## Local development

Use Linux x86-64 for the currently supported source development flow. This **developer** workspace uses Pixi to pin Mojo; users installing released Mojara do **not** need a Pixi workspace.

```bash
git clone https://github.com/mojara-framework/mojara.git
cd mojara
pixi install
pixi run bash scripts/build-cli.sh
bash scripts/test-native.sh
```

These commands exercise the first-party CLI and native C tests. Building a complete standalone SDK additionally requires the pinned Flare/JSON sources and other third-party build inputs; see [architecture](docs/ARCHITECTURE.md) and [release checklist](docs/RELEASE-CHECKLIST.md).

## Pull requests

Explain **what changed**, **why**, **which platforms**, **which tests ran**, and any **compatibility or security implications**. For new APIs, supply an example. For native C code, preserve explicit error handling, bounded buffers and FFI contracts.

The maintainers review PRs against the platform status and release checklist. CI must pass on the affected platforms before merging; every platform is tested separately.

## Reporting

- Bugs and feature requests: [GitHub Issues](https://github.com/mojara-framework/mojara/issues).
- Potential security vulnerabilities: follow [SECURITY.md](SECURITY.md), rather than posting an exploit publicly.
- Installation and end-user usage: [Mojara documentation](https://mojara.kasua.ng/docs/install.html).
