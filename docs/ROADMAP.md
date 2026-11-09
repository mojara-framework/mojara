# Roadmap

## Reliability first

- [x] Publish native Linux x86-64 and ARM64 packages as verified GitHub Release assets.
- [x] Add the full first-party Mojo and C source from the published SDK.
- [x] Add native C regression tests for uploads, file serving and telemetry.
- [x] Test native Mojo CLI and project generation on Linux x86-64 and ARM64.
- [ ] Pin and reproduce all third-party Mojo and C dependencies from source.
- [ ] Bring the missing transaction-pool bridge and core native extension sources into the source build.
- [x] Compile complete native Mojo framework, generated application and HTTP/static routes on Linux ARM64.
- [x] Verify live Mojo PostgreSQL and MariaDB prepared queries and transaction controls on ARM64.
- [x] Complete HTTP, WebSocket, databases, uploads and shutdown integration checks on ARM64.
- [x] Build and fresh-install native Conda packages for Linux x86-64 and ARM64, including real packaged PostgreSQL/MariaDB and HTTP smoke tests.
- [x] Verify zero unresolved installed native shared-library dependencies on clean hosts.
- [ ] Complete the native ABI/provenance audit and account for remaining system-runtime overlinking warnings.
- [ ] Compile the framework and all native bridges on Apple Silicon and run integration tests.
- [x] Publish and freshly install the Linux ARM64 GitHub Release package.
- [x] Publish Mojara 1.2.6 to the custom Conda channel for Linux x86-64 and ARM64.
- [ ] Compile and publish a verified macOS ARM64 package.
- [x] Add checksum-verified Linux multi-platform release automation.
- [ ] Add cryptographic build provenance and independent upstream source pinning.

## Windows

- [ ] Implement a documented Windows PowerShell front-end for the supported WSL2 workflow.
- [ ] Track the official native Mojo Windows compiler/runtime effort with Microsoft.
- [ ] Isolate Linux-only service management and POSIX library assumptions.
- [ ] Add Windows-native GitHub Actions checks when an official native Mojo toolchain is usable.
- [ ] Validate native sockets, TLS, filesystem, dynamic libraries and installers before offering an `.exe`.

## Project stewardship

- [ ] Establish API-compatibility expectations and semantic versioning policy.
- [x] Document first-party module and public function signatures in a complete Mojara source API reference.
- [ ] Publish tutorial-driven documentation and functional reference examples.
- [ ] Require CI and review before stable release publishing.

Do not interpret a checked box for CLI tests as a full platform support claim.
