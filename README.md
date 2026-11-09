# Mojara

Mojara is a native Mojo web framework. This repository initially hosts the **cross-platform portability development source** and GitHub Actions checks for Linux x86-64, Linux ARM64, and Apple Silicon macOS.

**Current stable release:** Mojara 1.2.5 for Linux x86-64 (including Windows via WSL2). The other targets are experimental until full native HTTP, WebSocket, database, upload, and packaging tests pass.

Documentation: https://mojara.kasua.ng/docs/

## CI

The `Mojara cross-platform CI` workflow compiles and tests the native Mojo CLI on three operating-system/architecture runners. The full native framework test is a separate release gate, not an implied pass when the CLI succeeds.

## Contributing

Please do not claim ARM64 or macOS as supported until native integration tests and packages have been verified. Windows native support is not part of the current Mojo toolchain.
