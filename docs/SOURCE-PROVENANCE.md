# Source provenance and reproducible builds

Mojara builds its first-party framework directly from the checked-in repository source:

- `source/mojara/`: Mojo framework and public API modules.
- `source/cli/`: native Mojo command-line tool.
- `source/native/`: native C/C++ bridge implementation.
- `tests/native/`: native regression checks.

## Independently pinned upstream Mojo dependencies

The external Flare, JSON, Morph and SQLite Mojo modules are retrieved directly from their original public repositories under [ehsanmok](https://github.com/ehsanmok). The exact Git commits and source-archive SHA-256 digests are recorded in `source/upstream/UPSTREAM.lock`.

`scripts/ci/bootstrap-source.sh` downloads and validates those archives without reading a previous Mojara binary or source distribution. `source/upstream/source-sha256.txt` selects an explicitly verified set of 347 upstream files. `source/upstream/compat.patch` records 22 Mojara-specific compatibility adjustments, including native loader changes. After patch application, every file is SHA-256 verified.

The upstream MIT license files are copied into the built SDK's `share/doc/mojara/licenses` directory. Native framework modules, CLI and C/C++ libraries are compiled afresh for the target architecture.

## Release verification

Linux x86-64 and Linux ARM64 release qualification compiles source, builds native Conda packages, inspects ELF dependencies and relocatable loader paths, then installs and runs Mojara on independent runners. macOS Apple Silicon qualification separately compiles the Mach-O native SDK and checks a clean-installed web application.

The binary ABI audit is implemented in `scripts/ci/audit-release-abi.sh`. It verifies ELF target architecture, shared-library providers declared in Conda metadata, loader paths, and the Linux GLIBC compatibility baseline. The audit supplements, rather than silences, packaging toolchain diagnostics.
