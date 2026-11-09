# Roadmap

## Reliability first

- [x] Publish Mojara v1.2.5 global install for Linux x86-64.
- [x] Add the full first-party Mojo and C source from the published SDK.
- [x] Add native C regression tests for uploads, file serving and telemetry.
- [x] Test native Mojo CLI and project generation on Linux x86-64 and ARM64.
- [ ] Pin and reproduce all third-party Mojo and C dependencies from source.
- [ ] Bring the missing transaction-pool bridge and core native extension sources into the source build.
- [ ] Compile full native Mojo applications on Linux ARM64.
- [ ] Complete HTTP, WebSocket, databases, uploads and shutdown integration checks on ARM64.
- [ ] Compile the framework and all native bridges on Apple Silicon and run integration tests.
- [ ] Publish and freshly install `linux-aarch64` and `osx-arm64` Conda packages.
- [ ] Add reproducible, signed/checksummed multi-platform release automation.

## Windows

- [ ] Implement a documented Windows PowerShell front-end for the supported WSL2 workflow.
- [ ] Track the official native Mojo Windows compiler/runtime effort with Microsoft.
- [ ] Isolate Linux-only service management and POSIX library assumptions.
- [ ] Add Windows-native GitHub Actions checks when an official native Mojo toolchain is usable.
- [ ] Validate native sockets, TLS, filesystem, dynamic libraries and installers before offering an `.exe`.

## Project stewardship

- [ ] Establish API-compatibility expectations and semantic versioning policy.
- [ ] Publish tutorial-driven documentation and functional reference examples.
- [ ] Require CI and review before stable release publishing.

Do not interpret a checked box for CLI tests as a full platform support claim.
