#!/usr/bin/env bash
# Entry point for `go generate ./...`.
# Builds clp-s for the current arch (glibc) and generates the embed Go file.
# Requires Docker. The generated files are intentionally excluded from .gitignore
# on main — they belong on the release branch only.
#
# Run from the repo root: go generate ./...

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

# Resolve arch before building so filenames match.
case "${GOARCH:-$(uname -m)}" in
    amd64|x86_64|k8) arch=amd64 ;;
    arm64|aarch64)   arch=arm64 ;;
    *) echo "ERROR: Unsupported arch: ${GOARCH:-$(uname -m)}. Set GOARCH=amd64|arm64." >&2; exit 1 ;;
esac

# The tarball is a purely intermediate artifact — build it in a temp dir and
# clean up on exit so only the generated .go file lands in the repo root.
tmp_dist=$(mktemp -d /tmp/clp-go-generate.XXXXXX)
trap 'rm -rf "${tmp_dist}"' EXIT

echo "==> Building clp-s tarball (glibc, ${arch})..."
GOARCH="${arch}" "${script_dir}/build-tarball-bazel.sh" \
    --output-dir "${tmp_dist}" \
    --libc glibc \
    --config "${repo_root}/clp-core.sh"

echo "==> Generating embed Go file for linux/${arch}..."
"${script_dir}/generate-embed-go.sh" \
    --arch "${arch}" \
    --output "${repo_root}/embed_linux_${arch}.go" \
    --tarball "${tmp_dist}/clp-s_linux_${arch}.tar.gz"

echo ""
echo "Generated (do not commit to main):"
echo "  embed_linux_${arch}.go"
