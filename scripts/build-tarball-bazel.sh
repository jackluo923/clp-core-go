#!/usr/bin/env bash
# Bazel-friendly wrapper around build-tarball.sh.
# Clones the CLP source repository (defined in clp-core.sh) to a stable
# cache directory under /tmp, fetches the configured branch, then builds
# exactly one target (arch + libc pair).
#
# Usage: ./scripts/build-tarball-bazel.sh \
#   --output-dir /path/to/output \
#   [--libc glibc|musl] \
#   [--config FILE]

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

config=""
output_dir="${repo_root}/dist"
libc="glibc"

while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)  output_dir="$2";  shift 2 ;;
        --libc)        libc="$2";        shift 2 ;;
        --config)      config="$2";      shift 2 ;;
        --help)        echo "Usage: $0 --output-dir PATH [--libc glibc|musl] [--config FILE]"; exit 0 ;;
        *)             echo "Unknown option: $1"; exit 1 ;;
    esac
done

case "${libc}" in
    glibc|musl) ;;
    *) echo "ERROR: --libc must be glibc or musl, got: ${libc}" >&2; exit 1 ;;
esac

if [[ -z "${config}" ]]; then
    config="${repo_root}/clp-core.sh"
fi

if [[ ! -f "${config}" ]]; then
    echo "ERROR: Config not found: ${config}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${config}"

# Clone or update the CLP source repository into a stable cache directory.
# The path is derived from the GitHub repo slug so it is reused across builds.
# Use a per-libc cache dir so glibc and musl builds can run in parallel
# (Bazel may run both genrules concurrently on the same machine).
clp_cache_dir="/tmp/clp-core-go-src/$(echo "${CLP_REPO}" | tr '/' '-')-${libc}"

if [[ -d "${clp_cache_dir}/.git" ]]; then
    echo "==> Updating CLP source at ${clp_cache_dir}..."
else
    echo "==> Cloning https://github.com/${CLP_REPO} ..."
    mkdir -p "$(dirname "${clp_cache_dir}")"
    GIT_TERMINAL_PROMPT=0 git clone \
        -c credential.helper= \
        "https://github.com/${CLP_REPO}.git" \
        "${clp_cache_dir}"
fi

# Fetch and reset to the exact fetched commit so the working tree is clean
# regardless of what was built previously from a different ref.
GIT_TERMINAL_PROMPT=0 git -C "${clp_cache_dir}" fetch origin "${CLP_REF}"
git -C "${clp_cache_dir}" reset --hard FETCH_HEAD

echo "==> Downloading CLP dependencies..."
(cd "${clp_cache_dir}" && bash "tools/scripts/deps-download/init.sh")

# Normalize arch from $GOARCH (set by `go generate` or Bazel genrule env),
# then uname -m. k8 is Bazel's internal name for amd64/x86_64.
case "${GOARCH:-$(uname -m)}" in
    amd64|x86_64|k8) target_arch=amd64 ;;
    arm64|aarch64)   target_arch=arm64 ;;
    *) echo "ERROR: Unsupported arch: ${GOARCH:-$(uname -m)}. Set GOARCH=amd64|arm64." >&2; exit 1 ;;
esac

echo "==> Building clp-s for linux/${target_arch} (${libc})..."

"${script_dir}/build-tarball.sh" \
    --clp-repo "${clp_cache_dir}" \
    --config "${config}" \
    --output-dir "${output_dir}" \
    --arch-filter "${target_arch}" \
    --libc-filter "${libc}"

echo "==> Tarball(s) written to ${output_dir}"
