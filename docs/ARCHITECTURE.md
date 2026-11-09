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

The Mojo framework, native CLI and first-party C bridges are compiled from the repository source for each target architecture. Flare, JSON, Morph and SQLite source files are retrieved directly from independently pinned upstream commits, adjusted with tracked compatibility patches and verified by file hashes. The external Mojo compiler and native connector development libraries are installed through platform-specific Conda dependencies. The transaction-pool extension still requires its complete independent native source and ABI verification. Do not reuse compiled libraries across CPU architectures.

## Runtime and platform boundaries

The HTTP server uses the Flare networking implementation. Native adapters are dynamically loaded, so library names, function ABI, TLS implementations, OS event loops, filesystem paths and processes must be tested per target. Linux systemd service management must not be treated as a universal deployment system.

## Packaging

`packaging/conda/` contains the original Conda packaging *staging* recipe. It consumes a separately built SDK payload and is **not** by itself a build-from-source recipe. See [Release gates](RELEASE-CHECKLIST.md).
