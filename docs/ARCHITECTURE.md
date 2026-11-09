# Architecture

Mojara consists of several layers:

```text
Mojo application (app.mojo)
        |
Mojara API / routing / auth / templates / DB modules
        |
Flare HTTP / WebSocket / network implementation
        |
Mojo runtime + platform-adapted native C bridges
        |
Linux kernel or macOS (native Windows planned)
```

## First-party modules

- `source/mojara/`: HTTP application facade, response, routing integrations, authentication, sessions, ORM, database interfaces, telemetry and lifecycle.
- `source/cli/mojara_cli.mojo`: native CLI, generator, compiler integration, watcher, Linux systemd deployment.
- `source/native/`: native C bridge implementations for web/static/upload, metrics and relational database operations.
- `tests/native/`: C API regression tests; independent of the Mojo compiler.

## Required external dependencies

The released SDK bundles precompiled, platform-specific components such as the Mojo compiler dependencies, Flare, JSON, native connector libraries and additional bridges. **Those binaries are not source files.** This repository preserves the complete first-party source shipped in v1.2.5, but a fully self-hosted source build remains incomplete until upstream dependency revisions and bridge build inputs have been pinned and validated. Do not copy x86-64 `.so` files into an ARM64 or macOS package.

## Runtime and platform boundaries

The HTTP server uses the Flare networking implementation. Native adapters are dynamically loaded, so library names, function ABI, TLS implementations, OS event loops, filesystem paths and processes must be tested per target. Linux systemd service management must not be treated as a universal deployment system.

## Packaging

`packaging/conda/` contains the original Conda packaging *staging* recipe. It consumes a separately built SDK payload and is **not** by itself a build-from-source recipe. See [Release gates](RELEASE-CHECKLIST.md).
