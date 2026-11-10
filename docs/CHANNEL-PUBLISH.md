# Mojara 1.2.9 Conda channel

The current release is [Mojara 1.2.9](https://github.com/mojara-framework/mojara/releases/tag/v1.2.9). Its native Linux x86-64, Linux ARM64 and Apple Silicon packages are served at https://mojara.kasua.ng/conda/.

## Publish release packages

Install the channel indexer:

```bash
pixi global install rattler-index -c conda-forge
```

On the authorized channel server, from the Mojara source repository, run:

```bash
bash scripts/release/publish-conda-channel.sh /absolute/path/to/conda
```

The script verifies all package SHA-256 checksums against the GitHub release before updating the channel indexes.

## Install Mojara

```bash
curl -fsSL https://raw.githubusercontent.com/mojara-framework/mojara/main/scripts/install.sh | bash
```

```bash
mojara doctor
```

For Docker, Windows and Intel Mac instructions, see the [public README](../README.md).
