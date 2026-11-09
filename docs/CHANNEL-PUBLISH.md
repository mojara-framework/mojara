# Publish Mojara to the hosted Conda channel

Mojara 1.2.7 is publicly available as native [Linux and Apple Silicon packages on GitHub](https://github.com/mojara-framework/mojara/releases/tag/v1.2.7). The independently hosted channel at https://mojara.kasua.ng/conda/ now contains Linux x86-64, Linux ARM64 and Apple Silicon packages and their indexes. This page documents how to safely update the channel in future releases.

The channel contains earlier Linux x86-64 releases. **Preserve those packages**; never replace the whole channel directory with an archive containing only the newest release. Publishing requires authorized access to the actual channel host or storage backend, not another VPS.

## Prepare the real channel host

Install the native channel indexer through Pixi:

~~~bash
pixi global install rattler-index -c conda-forge
~~~

From the checked-out Mojara repository, run the publication script using the **actual absolute filesystem directory** served by the existing `/conda/` URL:

~~~bash
bash scripts/release/publish-conda-channel.sh /actual/path/to/conda
~~~

The script verifies the existing channel is complete; downloads all three release binaries and their GitHub SHA-256 checksums; refuses to overwrite different packages; retains earlier releases; regenerates `repodata.json` using `rattler-index` for `linux-64`, `linux-aarch64`, `osx-arm64`, and `noarch`; and checks the version, file name and checksum inside the new indexes.

The channel directory path depends on the host's Nginx or object-storage configuration. Do not guess it. The script does not access unrelated servers or publish automatically.

## Verify the public channel

~~~bash
curl -fsS https://mojara.kasua.ng/conda/linux-64/repodata.json -o /tmp/mojara-linux-64.json
curl -fsS https://mojara.kasua.ng/conda/linux-aarch64/repodata.json -o /tmp/mojara-linux-aarch64.json
curl -fsS https://mojara.kasua.ng/conda/osx-arm64/repodata.json -o /tmp/mojara-osx-arm64.json
~~~

On a fresh Linux x86-64, Linux ARM64 or Apple Silicon macOS machine, run:

~~~bash
pixi global install 'mojara==1.2.7' \
  -c https://mojara.kasua.ng/conda/ \
  -c https://conda.modular.com/max/ \
  -c conda-forge
mojara version
mojara doctor
~~~

The primary README uses the hosted Conda channel for installation. Keep GitHub downloads as a fallback.

The completed channel publication is recorded in [issue #12](https://github.com/mojara-framework/mojara/issues/12). Native ABI/provenance hardening is tracked in [issue #9](https://github.com/mojara-framework/mojara/issues/9).
