# clp-core-go

A Go library for [CLP](https://github.com/y-scope/clp) structured log
compression and search. It embeds the `clp-s` binary directly into the Go
library, so consumers require no external installation or network access at
runtime.

> **Note:** The embedded binary files are gitignored and never committed —
> they are built from source at compile time. Two ways to build the library:
>
> | Method | Command | Requires |
> |--------|---------|----------|
> | **`go generate`** | `go generate ./... && go build ./...` | Docker |
> | **Bazel** | `bazel build //:clp` | Docker + Bazel |

## Usage

```go
import clp "github.com/y-scope/clp-core-go"

stdout, stderr, err := clp.Run("c", "archive.clp", "input.log")
if err != nil {
    log.Fatal(err)
}
```

`clp.Run` accepts the same subcommands as the `clp-s` CLI:

```
c  <archive> <input>    compress
x  <archive> <output>   decompress
s  <archive> <query>    search
```

On the first call, the embedded binary is extracted to a per-process temp
directory (`/tmp/clp-core-go-<timestamp>-<random>/`) and reused for the
lifetime of the process. If extraction fails, all subsequent calls return the
same error.

The temp directory is removed automatically on `SIGINT`, `SIGTERM`, or
`SIGQUIT`. If your program exits normally without one of those signals, the
directory is left behind until the OS cleans it up. To remove it eagerly on a
normal exit, call `clp.Cleanup()`.

### Alpine Linux

The musl variant requires the C++ runtime, which Alpine does not install by
default. Add it once to your image:

```dockerfile
RUN apk add --no-cache libstdc++
```

Or equivalently on the host: `apk add libstdc++`.

## How it works

**Build time.** `clp-s` is compiled inside a Docker container that matches the
target platform and libc variant (glibc or musl). The resulting binary and its
shared library dependencies are bundled into a tarball, base64-encoded, and
written into a generated Go source file that is compiled into the library.

**Runtime.** The first call to `clp.Run()` decodes the embedded tarball, writes
it to a temporary directory with permissions preserved from the archive, and
executes `clp-s` as a subprocess. Subsequent calls reuse the extracted
directory.

## Building

### `go generate`

Builds `clp-s` for the host architecture (glibc) and generates the embed Go
file. Docker is required.

```bash
go generate ./...
go build ./...
```

`go generate` produces one file in the repo root:

```
embed_linux_amd64.go      # generated Go source
```

The intermediate tarball is built in a temp directory and removed automatically.
The generated file is listed in `.gitignore` and should not be committed.

### Bazel

#### Prerequisites

- [Bazel](https://bazel.build/install) (or [Bazelisk](https://github.com/bazelbuild/bazelisk) to auto-select the version via `.bazelversion`)
- [Docker](https://docs.docker.com/get-docker/)
- Internet access on the first build (to clone the CLP source repository)

#### Commands

The build is self-contained. On first run it clones the CLP source into
`/tmp/clp-core-go-src/`; on subsequent builds it fetches and checks out the
configured ref, so the cache is always up to date.

```bash
# Default: host architecture, glibc
bazel build //:clp

# Cross-compile to arm64 (requires QEMU/binfmt_misc for Docker cross-execution)
bazel build //:clp --platforms=@rules_go//go/toolchain:linux_arm64

# musl libc (Alpine, static-friendly)
bazel build //:clp --define libc=musl

# Combined
bazel build //:clp --platforms=@rules_go//go/toolchain:linux_arm64 --define libc=musl
```

## Configuration — `clp-core.sh`

`clp-core.sh` controls which CLP commit to build and which Docker image to use
for each platform and libc combination. It is a plain shell file — no external
parser required.

```bash
CLP_REPO="y-scope/clp"
CLP_REF="main"   # branch name, tag, or commit SHA

CLP_TARGET_AMD64_GLIBC_DOCKER_PLATFORM="linux/amd64"
CLP_TARGET_AMD64_GLIBC_IMAGE="ghcr.io/y-scope/clp/clp-core-dependencies-x86-manylinux_2_28:main"
CLP_TARGET_AMD64_GLIBC_TARBALL_SUFFIX="amd64"

CLP_TARGET_AMD64_MUSL_DOCKER_PLATFORM="linux/amd64"
CLP_TARGET_AMD64_MUSL_IMAGE="ghcr.io/y-scope/clp/clp-core-dependencies-x86-musllinux_1_2:main"
CLP_TARGET_AMD64_MUSL_TARBALL_SUFFIX="amd64_musl"

CLP_TARGET_ARM64_GLIBC_DOCKER_PLATFORM="linux/arm64"
CLP_TARGET_ARM64_GLIBC_IMAGE="ghcr.io/y-scope/clp/clp-core-dependencies-aarch64-manylinux_2_28:main"
CLP_TARGET_ARM64_GLIBC_TARBALL_SUFFIX="arm64"

CLP_TARGET_ARM64_MUSL_DOCKER_PLATFORM="linux/arm64"
CLP_TARGET_ARM64_MUSL_IMAGE="ghcr.io/y-scope/clp/clp-core-dependencies-aarch64-musllinux_1_2:main"
CLP_TARGET_ARM64_MUSL_TARBALL_SUFFIX="arm64_musl"
```

The `IMAGE` field for each target specifies the Docker build environment. It
accepts any local or registry image; if not present locally, it is pulled
automatically. This allows organisations to substitute internally built or
mirrored images without changing the build scripts.

## Smoke test

A minimal smoke-test binary lives under `cmd/testrun`. It calls
`clp.Run("--help")` and prints the output, verifying that the embedded binary
can be extracted and executed:

```bash
bazel run //cmd/testrun
```

## Build flags reference

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--platforms=@rules_go//go/toolchain:linux_arm64` | any Go toolchain platform | host | Target platform for the Go library and embedded `clp-s` binary |
| `--define libc=musl` | `musl` | glibc | Link against musl instead of glibc |

---

## Design rationale

This section documents why `clp-s` is embedded rather than distributed
separately. It is intended for security reviewers and engineers evaluating
whether this approach is appropriate for their organisation.

### What is clp-s?

`clp-s` is a high-performance structured log compression and search engine
written in C++ by [YScope](https://github.com/y-scope). It compresses log files
into a binary archive format and can search the compressed data without full
decompression — analogous to a specialised `tar+gzip` with built-in query
support. There is no equivalent Go implementation.

### Why not use an existing distribution channel?

YScope provides several ways to obtain `clp-s`:

| Method | Description | Limitation in corporate environments |
|--------|-------------|--------------------------------------|
| **System package** | Debian/RPM via YScope PPA | Adding third-party PPAs is prohibited by many security policies |
| **Python package** | `pip install clp-core-py` | Requires a Python environment; does not integrate into a Go module or monorepo |
| **Build from source** | Clone and compile manually | Requires the full C++ toolchain and all of CLP's build dependencies on every developer and CI machine |
| **This library** | Compiled in CI, embedded at build time | Works in Go monorepos; no runtime dependencies; binary fully traceable to source |

### Why not CGO or a Go reimplementation?

**Correctness.** CLP's archive format is a binary encoding in which a single
incorrect bit produces silent data corruption or unreadable archives. There is
one correct, tested implementation — the canonical C++ codebase. Wrapping it
via CGO or reimplementing it in Go would introduce a second codebase that must
be kept byte-for-byte equivalent with the original, validated against the full
CLP test suite, and updated in lockstep with every upstream change. That
maintenance obligation is not acceptable for a compression engine where data
integrity is the primary requirement.

**Performance and complexity.** CLP has been heavily optimised for throughput
and memory efficiency. Those optimisations are non-trivial to replicate and
would require deep expertise in the internals to validate correctly.

**Build system incompatibility.** CGO has no equivalent to CLP's Docker-based
reproducible build environments. Porting CLP's transitive C++ dependency tree
(Boost, marisa-trie, and others) into Go's CGO framework would require wiring
up each dependency's CMake configuration and compiler flags manually.

### Why compile internally rather than use YScope's pre-built binaries?

Many organisations require that all production binaries be compiled from
auditable source within their own infrastructure, so that:

- the exact source commit is known and traceable,
- the compiler, flags, and dependencies are controlled internally,
- build logs are retained in the organisation's own CI systems, and
- no opaque binaries from external distribution channels are introduced.

This library satisfies those requirements. `clp-s` is compiled from a pinned
commit of the public [y-scope/clp](https://github.com/y-scope/clp) repository,
inside a Docker container whose image is specified in `clp-core.sh`, by the
organisation's own CI pipeline. The resulting binary is embedded into the Go
binary at compile time and ships as a single, self-contained artifact with a
clear chain of custody from source to production.

### Prior art

Embedding pre-compiled artifacts in Go packages is an established pattern:

- **[Tailscale](https://github.com/tailscale/tailscale)** embeds eBPF bytecode
  (compiled by `bpf2go`) via `//go:embed` for kernel-level packet filtering in
  its DERP relay servers.
- **[ncruces/go-sqlite3](https://github.com/ncruces/go-sqlite3)** embeds the
  SQLite C library compiled to WASM via `//go:embed` and runs it in-process via
  [wazero](https://github.com/tetratelabs/wazero) — zero CGO, full upstream
  SQLite compatibility.
- **[amenzhinsky/go-memexec](https://github.com/amenzhinsky/go-memexec)** is a
  general-purpose library that implements the same embed-and-exec pattern used
  by this library.

## Security properties

| Property | Detail |
|----------|--------|
| **Provenance** | `clp-s` is built from the [y-scope/clp](https://github.com/y-scope/clp) public repository at the commit pinned in `clp-core.sh`. |
| **Build environment** | Compiled inside Docker images published by the CLP team at `ghcr.io/y-scope/clp/`, pinned by tag in `clp-core.sh`. Organisations may substitute their own mirrored or internally built images. |
| **No runtime network access** | The binary is inlined at build time. `clp.Run()` performs no network requests. |
| **Extraction safety** | The tar extractor rejects path traversal (`../`), absolute paths, symlinks, and hardlinks. Files are created with the exact permissions recorded in the tarball. |
| **No elevated privileges** | `clp-s` runs as the calling process's user with no additional capabilities. |
| **Temp directory isolation** | Each process extracts to a uniquely named directory (`/tmp/clp-core-go-<timestamp>-<random>/`). The directory is removed on `SIGINT`, `SIGTERM`, or `SIGQUIT`. |
