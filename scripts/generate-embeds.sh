#!/usr/bin/env bash
# Generates embed_linux_*.go files from pre-built tarballs.
# Called by CI after building tarballs; the generated files are committed so
# that consumers can use the library via `go get` without Bazel.
# Only glibc variants are committed — musl requires Bazel (--define libc=musl).
#
# Usage: ./scripts/generate-embeds.sh [--dist-dir ./bin/dist] [--out-dir .] [--config FILE]

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

config="${repo_root}/clp-core.sh"
dist_dir="${repo_root}/bin/dist"
out_dir="${repo_root}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dist-dir) dist_dir="$2"; shift 2 ;;
        --out-dir)  out_dir="$2";  shift 2 ;;
        --config)   config="$2";   shift 2 ;;
        --help)     echo "Usage: $0 [--dist-dir PATH] [--out-dir PATH] [--config FILE]"; exit 0 ;;
        *)          echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -f "${config}" ]]; then
    echo "ERROR: Config not found: ${config}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${config}"

# Generate glibc embed files only. Musl can't be expressed with standard Go
# build tags, so musl users must build with Bazel (--define libc=musl).
for arch in amd64 arm64; do
    key="CLP_TARGET_${arch^^}_GLIBC"
    suffix_var="${key}_TARBALL_SUFFIX"
    tarball_suffix="${!suffix_var}"
    tarball="${dist_dir}/clp-s_linux_${tarball_suffix}.tar.gz"
    out_file="${out_dir}/embed_linux_${arch}.go"

    if [[ ! -f "${tarball}" ]]; then
        echo "ERROR: ${tarball} not found. Run build-tarball.sh first." >&2
        exit 1
    fi

    GOARCH="${arch}" "${script_dir}/generate-embed-go.sh" \
        --output "${out_file}" \
        --tarball "${tarball}"
done

echo "Embed generation complete."
