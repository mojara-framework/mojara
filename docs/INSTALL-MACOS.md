# Install Mojara on macOS

Mojara supports Macs with Apple Silicon (ARM64). Install the latest [Pixi](https://pixi.sh/latest/installation/) for macOS, then run:

```bash
pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
```

## Create and run a Mojara application

```bash
mojara version
mojara doctor
mojara new hello-mojara
cd hello-mojara
mojara dev
```

Applications run directly with the native Mojo runtime; a Python or Node.js server is not required.

The official [Mojara 1.2.7 release](https://github.com/mojara-framework/mojara/releases/tag/v1.2.7) also provides an architecture-specific native Conda package and checksums.

**Platform:** Apple Silicon only. Macs with Intel processors are not currently supported.
