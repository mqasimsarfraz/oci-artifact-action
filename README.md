# OCI Artifact Action

Share OCI archives, OCI layouts, container images, Helm artifacts, WASM
artifacts, SBOMs, and other OCI content between isolated GitHub Actions jobs
without publishing them to a registry.

The action packages a file or directory, uploads it as a GitHub workflow
artifact, and derives the artifact name from a caller-provided correlation key.
A later job uses the same correlation key to download and extract the payload.

## Usage

### Share a container image between jobs

Buildx can export a single- or multi-platform container image as an OCI archive.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
      - uses: docker/setup-buildx-action@37fe631027851001ddb9b187196cc803df7f5f0e
      - uses: docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          outputs: type=oci,dest=${{ runner.temp }}/image.tar
      - uses: mqasimsarfraz/oci-artifact-action@v1
        with:
          operation: upload
          path: ${{ runner.temp }}/image.tar
          correlation-id: app-${{ github.sha }}

  consume:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: mqasimsarfraz/oci-artifact-action@v1
        id: image
        with:
          operation: download
          correlation-id: app-${{ github.sha }}
      - name: Publish the image
        run: |
          skopeo copy \
            --multi-arch all \
            "oci-archive:${{ steps.image.outputs.path }}" \
            docker://ghcr.io/example/app:${{ github.sha }}
```

The downloaded path points to the original `image.tar` file.

### Share an OCI layout directory

```yaml
- uses: mqasimsarfraz/oci-artifact-action@v1
  with:
    operation: upload
    path: ${{ runner.temp }}/oci-layout
    correlation-id: gadgets-${{ github.sha }}
```

```yaml
- uses: mqasimsarfraz/oci-artifact-action@v1
  id: gadgets
  with:
    operation: download
    correlation-id: gadgets-${{ github.sha }}
- run: oras repo tags --oci-layout "${{ steps.gadgets.outputs.path }}"
```

### Download from another workflow run

GitHub's artifact API requires the source workflow run ID and a token when an
artifact is downloaded outside the current run.

```yaml
- uses: mqasimsarfraz/oci-artifact-action@v1
  id: image
  with:
    operation: download
    correlation-id: app-linux-amd64
    run-id: ${{ inputs.source-run-id }}
    github-token: ${{ github.token }}
```

Use `repository: owner/repository` as well when the source artifact belongs to
another repository. The token must be able to read actions in that repository.

## Correlation

`name` and `correlation-id` are converted into a deterministic artifact name:

```text
<name slug>-<correlation slug>-<12 character correlation hash>
```

Upload and download invocations with the same values resolve to the same
artifact. The hash prevents two keys that normalize to the same slug from
colliding. If `correlation-id` is omitted, it defaults to the current workflow
run ID and attempt, which is sufficient for sharing between jobs in one run.

The generated name is available as the `artifact-name` output.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `operation` | Yes | | `upload` or `download` |
| `path` | For upload | | File or directory to package |
| `correlation-id` | No | Current run and attempt | Correlation key |
| `name` | No | `oci-artifact` | Artifact name prefix |
| `destination` | No | Runner temporary directory | Download extraction directory |
| `retention-days` | No | `1` | Artifact retention |
| `compression-level` | No | `0` | GitHub artifact compression level |
| `overwrite` | No | `false` | Replace an artifact with the same name |
| `run-id` | No | Current run | Source workflow run |
| `repository` | No | Current repository | Source repository |
| `github-token` | With `run-id` | | Token for cross-run downloads |

## Outputs

| Output | Description |
|---|---|
| `path` | Original upload path or extracted download path |
| `artifact-name` | Deterministic GitHub artifact name |
| `correlation-id` | Correlation key used by the action |
| `artifact-id` | GitHub artifact ID for uploads |
| `artifact-url` | GitHub artifact URL for uploads |
| `artifact-digest` | GitHub artifact digest for uploads |

## Design

- OCI content is treated as an opaque payload, so the action does not require a
  particular container runtime or OCI client.
- Files and directories are wrapped in an uncompressed tar envelope to preserve
  layout, permissions, and symbolic links below the payload root.
- A SHA-256 checksum is stored inside the artifact and verified before
  extraction. GitHub's artifact digest provides an additional integrity check.
- Archive entries are constrained to the recorded payload root before
  extraction.
- Artifact compression defaults to `0` because OCI layers and archives are
  normally already compressed.

The action currently targets runners with Bash, `tar`, and either `sha256sum`
or `shasum`, including GitHub-hosted Linux and macOS runners.

## License

[MIT](LICENSE)
