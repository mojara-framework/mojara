# Dependencies and reproducible builds

Mojara contains a first-party Mojo framework, native C bridges and a Mojo CLI built for each supported platform. Four external Mojo module source trees are pinned to upstream Git revisions and verified by SHA-256.

| Dependency | Purpose | Reproducibility requirement |
| --- | --- | --- |
| Mojo compiler 1.2.0 | Compiles CLI and applications | Pin matching official compiler |
| Flare | HTTP, WebSocket and network foundation | Pin source revision, build FFI bridges per platform |
| Mojo JSON and supporting modules | JSON parsing/serialization | Pin source revision and preserve upstream license |
| libpq | PostgreSQL adapter | Build/link for each target |
| MariaDB/MySQL connector | Database adapter | Build/link for each target |
| SQLite and libsodium | Optional database/crypto | Link target-specific libraries |
| Mojara transaction-pool extension | Database pool interfaces | Check in buildable first-party extension sources |
| Native Mojo/C adapter libraries | Filesystem, upload, metrics, database | Build from repository source |

Upstream revisions for the dependencies copied into the published SDK must be identified and locked before a fully reproducible independent source build can be certified. Until then, the provided recipe packages an already-built payload.

See [Third-party notices](THIRD_PARTY_LICENSES.md). Do not redistribute third-party code without preserving license and attribution files. Never copy Linux x86-64 ELF shared objects into ARM64 or macOS packages.
