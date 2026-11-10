# Install Mojara

Mojara is available for Linux x86-64 and ARM64, including Ubuntu on Windows WSL2.

## Install with Pixi

Install [Pixi](https://pixi.sh/latest/installation/) if needed, then install Mojara:

```bash
pixi global install 'mojara==1.2.9' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
```

## Alternative: one-command installer

The official release installer also installs Pixi if needed and checks the SHA-256 checksum of the Mojara package before installing:

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
