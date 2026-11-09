# Publish Mojara to the hosted Conda channel

Mojara 1.2.6 is publicly available as separate [Linux x86-64 and ARM64 packages on GitHub](https://github.com/mojara-framework/mojara/releases/tag/v1.2.6). The independently hosted channel at https://mojara.kasua.ng/conda/ must also contain the new files and updated indexes before applications can install 1.2.6 by package name.

The channel contains earlier Linux x86-64 releases. **Preserve those packages**; never replace the whole channel directory with an archive containing only the newest release. Publishing requires authorized access to the actual channel host or storage backend, not another VPS.

## Prepare the real channel host

Install a current channel indexer in an isolated Python environment:

~~~bash
python3 -m venv ~/mojara-conda-index
~/mojara-conda-index/bin/pip install 'conda-index>=0.13,<0.14'
~~~

From the checked-out Mojara repository, run the publication script using the **actual absolute filesystem directory** served by the existing \`/conda/\` URL:

~~~bash
CONDA_INDEX_PYTHON=~/mojara-conda-index/bin/python \
  bash scripts/release/publish-conda-channel.sh /actual/path/to/conda
~~~

The script verifies the existing channel is complete; downloads both release binaries and GitHub SHA-256 checksums; refuses to overwrite different packages; retains earlier releases; regenerates \`repodata.json\` for \`linux-64\`, \`linux-aarch64\`, and \`noarch\`; and checks the version, file name and checksum inside the new indexes.

The channel directory path depends on the host's Nginx or object-storage configuration. Do not guess it. The script does not access unrelated servers or publish automatically.

## Verify the public channel

~~~bash
curl -fsS https://mojara.kasua.ng/conda/linux-64/repodata.json -o /tmp/mojara-linux-64.json
curl -fsS https://mojara.kasua.ng/conda/linux-aarch64/repodata.json -o /tmp/mojara-linux-aarch64.json
~~~

On a fresh Linux x86-64 or Linux ARM64 machine, run:

~~~bash
pixi global install 'mojara==1.2.6' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
mojara version
mojara doctor
~~~

Verify actual installation on each architecture before changing the primary README installation commands from direct GitHub Release assets to channel installation. Keep GitHub downloads as a fallback.

The publication is tracked in [issue #12](https://github.com/mojara-framework/mojara/issues/12); remaining ABI/provenance work is tracked in [issue #9](https://github.com/mojara-framework/mojara/issues/9).
