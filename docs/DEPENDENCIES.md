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

The exact upstream Git revisions, source archive SHA-256 hashes and per-file compatibility results are recorded in `source/upstream/`. The native Conda recipes package freshly compiled platform-specific SDK payloads. Complete transaction-pool extension source and its native ABI verification are tracked separately in [source reproducibility issue #3](https://github.com/mojara-framework/mojara/issues/3).

See [Third-party notices](THIRD_PARTY_LICENSES.md). Do not redistribute third-party code without preserving license and attribution files. Never copy Linux x86-64 ELF shared objects into ARM64 or macOS packages.
