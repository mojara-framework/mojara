# Mojara v1.2.5 source provenance

The first-party implementation was recovered from the **published official Mojara v1.2.5 Linux x86-64 Conda package**, not reconstructed from examples.

Published source archive:
- Package: [mojara-1.2.5-hb0f4dca_0.conda](https://mojara.kasua.ng/conda/linux-64/mojara-1.2.5-hb0f4dca_0.conda)
- SHA-256: `838bb8d3404a8f481e2ec18236a539599dd66d151ae6a758675e6b4f1b893e02`
- Source path within package: `opt/mojara/share/mojara/source/`

Inventory:
- 26 first-party Mojo framework modules in `source/mojara/`.
- 8 first-party native C bridge implementations in `source/native/`.
- 1 first-party CLI source in `source/cli/`.

A clean GitHub clone was compared against the released SDK on Linux. All **35** published source paths were present. The framework modules and native C files matched the release, except for normalized final newline differences. The CLI source intentionally differs because this repository contains portability preparation (host CPU selection, macOS dynamic library suffix and Linux-only systemd checks).

The included C regression tests were recovered from a prior v1.0.0 SDK source test bundle and were **executed successfully against the v1.2.5 native implementations** on Linux x86-64. They are additional QA assets, not claimed to have been present in the v1.2.5 source folder.

## Limits

The v1.2.5 SDK bundles third-party precompiled Mojo modules, dynamic native connectors and a transaction-pool extension for which **not all source build inputs appear in that SDK source directory**. This GitHub repository does not yet provide a fully self-contained, dependency-locked source build. See [issue #3](https://github.com/mojara-framework/mojara/issues/3) for the remaining work.

