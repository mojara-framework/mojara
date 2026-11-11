# Install Mojara

Mojara 1.2.10 is available for Linux x86-64, including Ubuntu on Windows WSL2. Linux ARM64 continues to use the qualified 1.2.9 package.

## Install with Pixi

Install [Pixi](https://pixi.sh/latest/installation/) if needed, then install Mojara:

```bash
pixi global install 'mojara==1.2.10' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
```

Linux ARM64 users can use the same Pixi command with `mojara==1.2.9` until the next native ARM64 package is qualified.

## Alternative: one-command installer

The official GitHub release installer also installs Pixi if needed and verifies the downloaded package. It follows the GitHub-tagged release, which may differ from the latest Conda-channel Linux x86-64 package:

```bash
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/install.sh | bash
```

Use either installation method. On Windows, run the commands **inside Ubuntu in WSL2**.

## Start a project

```bash
mojara version
mojara new hello-mojara
cd hello-mojara
mojara dev
```

[GitHub releases](https://github.com/mojara-framework/mojara/releases/tag/v1.2.9) also provide architecture-specific package downloads and SHA-256 checksums.
