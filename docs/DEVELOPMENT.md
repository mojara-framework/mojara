# Development guide

This repository is the canonical first-party Mojara source tree.

## Build the developer CLI

```bash
pixi install
pixi run bash scripts/build-cli.sh
./build/bin/mojara version
```

Runs on Linux x86-64 and Linux ARM64; macOS Apple Silicon is a target but is not yet fully certified.

## Native C regression tests

```bash
bash scripts/test-native.sh
```

Tests real filesystem boundaries, multipart uploads and concurrency-sensitive telemetry. Native regression CI runs on Linux x86-64 and ARM64.

## Full framework

The source under `source/mojara` depends on third-party Mojo source modules and platform-specific native libraries distributed with the official SDK. It is **not yet independently reproducible** from this repository alone. The Conda recipe in `packaging/conda` packages an already-staged SDK payload.

See [architecture](ARCHITECTURE.md), [dependencies](DEPENDENCIES.md), [roadmap](ROADMAP.md) and [release checklist](RELEASE-CHECKLIST.md).

## Running CI

GitHub Actions runs on changes. Under the **Actions** tab, choose the workflow and **Run workflow** for an on-demand check. Observe the specific job status rather than treating a green CLI build as proof that HTTP or databases pass.
