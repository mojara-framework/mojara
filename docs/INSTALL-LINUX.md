# Install Mojara on Linux

Mojara publishes native Linux x86-64 and ARM64 Conda packages through the [official GitHub release](https://github.com/mojara-framework/mojara/releases/tag/v1.2.6).

## Linux ARM64

```bash
curl -fLO https://github.com/mojara-framework/mojara/releases/download/v1.2.6/mojara-1.2.6-he8cfe8b_0.conda
pixi global install --path ./mojara-1.2.6-he8cfe8b_0.conda \
  -c https://conda.modular.com/max/ -c conda-forge
```

## Linux x86-64 and WSL2

```bash
curl -fLO https://github.com/mojara-framework/mojara/releases/download/v1.2.6/mojara-1.2.6-hb0f4dca_0.conda
pixi global install --path ./mojara-1.2.6-hb0f4dca_0.conda \
  -c https://conda.modular.com/max/ -c conda-forge
```

Review [SHA256SUMS](https://github.com/mojara-framework/mojara/releases/download/v1.2.6/SHA256SUMS) to verify downloaded packages.

## Create an application

```bash
mojara version
mojara doctor
mojara new hello-mojara
cd hello-mojara
mojara dev
```

The custom Mojara Conda channel is separately hosted. Its ARM64 index is not yet updated; the verified installation path for this release is downloading the matching GitHub Release asset and installing it through Pixi.
