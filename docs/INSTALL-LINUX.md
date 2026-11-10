# Install Mojara

Mojara is available for Linux x86-64 and ARM64, including Ubuntu on Windows WSL2.

Install with Pixi:

```bash
pixi global install 'mojara==1.2.9' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
```

## Start a project

```bash
mojara version
mojara new hello-mojara
cd hello-mojara
mojara dev
```

[GitHub releases](https://github.com/mojara-framework/mojara/releases/tag/v1.2.9) also provide architecture-specific package downloads and SHA-256 checksums.
