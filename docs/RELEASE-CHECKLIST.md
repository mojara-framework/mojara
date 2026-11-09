# Release checklist

This is the minimum gate for publishing any new Mojara package. Passing the CLI-only workflow does not complete this checklist.

- [ ] Tag a reviewed source commit and record the Mojo compiler version.
- [ ] Pin Flare, JSON and other upstream source revisions; verify third-party licensing.
- [ ] Build every native bridge from source for the target OS and CPU.
- [ ] Precompile the first-party Mojo framework using the matching compiler and dependencies.
- [ ] Build a representative application and check HTTP GET/POST routing and templates.
- [ ] Test WebSockets, SSE, static files, multipart uploads and relevant security regression cases.
- [ ] Test MySQL/PostgreSQL connections, prepared statements, transactions and connection-pool shutdown.
- [ ] Test concurrent traffic, graceful shutdown, reload and local CLI workflows.
- [ ] Create a Conda package with only required platform binaries, correct ELF/Mach-O architecture and dependency metadata.
- [ ] Verify relative ELF loader paths, zero unresolved installed dependencies and resolve package overlinking warnings.
- [ ] Verify a **fresh global installation** from the public channel on the actual target OS and architecture.
- [ ] Verify the documentation and package release notes match the actual supported targets.
- [ ] Publish the checksums/artifacts, then update the channel index.
- [ ] Keep the previous known-good release available for rollback.

## Current release

Mojara **1.2.6** is publicly released with verified Linux x86-64 and ARM64 packages and SHA-256 checksums on GitHub. The custom Conda channel still needs the ARM64 package and updated index. Independent third-party source pinning, remaining overlinking diagnostics and macOS/native Windows qualification remain outstanding.
