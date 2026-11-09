# Mojara

**Mojara** is an open-source web framework built with the Mojo programming language. It offers native HTTP routing, APIs, authentication, MySQL/PostgreSQL integration, sessions, WebSockets, and a native developer CLI.

**Stable release:** Mojara 1.2.5 for Linux x86-64 (including Windows with WSL2). Other platforms are experimental.

## Cross-platform CI

The **Mojara cross-platform CI** workflow builds the native Mojo command-line tool and runs the project-generator smoke test on:

- Ubuntu Linux x86-64 (`ubuntu-24.04`)
- Ubuntu Linux ARM64 (`ubuntu-24.04-arm`)
- macOS Apple Silicon (`macos-15`)

It runs automatically on pushes and pull requests and can also be started manually from GitHub Actions. These checks do **not** yet prove the complete Mojara HTTP server works on the new platforms. Full framework precompilation, native bridges, database integration, WebSocket and packaging require separate validation.

See [CI guide](docs/CROSS-PLATFORM.md), [official documentation](https://mojara.kasua.ng/docs/) and [the current release](https://mojara.kasua.ng/docs/releases.html).

### Install Mojara (supported Linux x86-64)

```bash
pixi global install "mojara==1.2.5" -c https://mojara.kasua.ng/conda/ -c https://conda.modular.com/max/ -c conda-forge
mojara new my-app
cd my-app
mojara dev
```

**Do not use this repository's experimental source to replace your stable installation.**
