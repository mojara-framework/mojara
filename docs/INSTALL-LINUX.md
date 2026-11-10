# Install Mojara

Mojara is available for Linux x86-64 and ARM64, including Ubuntu on Windows WSL2.

Install or upgrade Mojara with the official release installer:

```bash
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/install.sh | bash
```

This verifies the SHA-256 checksum published with the release package and installs Mojara with Pixi and the compatible Mojo compiler. On Windows, run this command inside Ubuntu in WSL2.

## Start a project

```bash
mojara version
mojara new hello-mojara
cd hello-mojara
mojara dev
```

[GitHub releases](https://github.com/mojara-framework/mojara/releases/tag/v1.2.9) also provide architecture-specific package downloads and SHA-256 checksums.
