#!/usr/bin/env bash
# Builds clp-s tarballs driven by clp-core.sh config.
#
# Sources clp-core.sh to get repo, branch, binary, and per-target settings.
# For each matching target, compiles CLP inside Docker and creates a tarball.
#
# Prerequisites: Docker
# Usage: ./scripts/build-tarball.sh [--clp-repo /path/to/clp] [--output-dir ./bin/dist]
#   [--arch-filter amd64|arm64] [--libc-filter glibc|musl] [--config FILE]

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

clp_repo=""
config="${repo_root}/clp-core.sh"
output_dir="${repo_root}/bin/dist"
cores="$(nproc 2>/dev/null || echo 4)"
arch_filter=""
libc_filter=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --clp-repo)    clp_repo="$2";     shift 2 ;;
        --config)      config="$2";       shift 2 ;;
        --output-dir)  output_dir="$2";   shift 2 ;;
        --cores)       cores="$2";        shift 2 ;;
        --arch-filter) arch_filter="$2";  shift 2 ;;
        --libc-filter) libc_filter="$2";  shift 2 ;;
        --help)        sed -n '/^# Usage:/,/^[^#]/{ /^#/s/^# \?//p; }' "$0"; exit 0 ;;
        *)             echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -f "${config}" ]]; then
    echo "ERROR: Config not found: ${config}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${config}"

echo "==> Config from ${config}:"
echo "    ref: ${CLP_REF}"
echo ""

if [[ -z "${clp_repo}" ]]; then
    echo "ERROR: --clp-repo is required (path to CLP source checkout)" >&2
    exit 1
fi

clp_packaging="${clp_repo}/components/core/tools/packaging"
if [[ ! -f "${clp_packaging}/common/bundle-libs.sh" ]]; then
    echo "ERROR: bundle-libs.sh not found at ${clp_packaging}/common/bundle-libs.sh" >&2
    exit 1
fi

mkdir -p "${output_dir}"

# Iterate over the fixed set of known targets.
# Bash indirect variable expansion (${!var}) looks up a variable whose name is
# stored in another variable — used here to select per-target config fields
# without an associative array or external parser.
for arch in amd64 arm64; do
    for libc in glibc musl; do
        [[ -n "${arch_filter}" && "${arch}" != "${arch_filter}" ]] && continue
        [[ -n "${libc_filter}" && "${libc}" != "${libc_filter}" ]] && continue

        key="CLP_TARGET_${arch^^}_${libc^^}"
        docker_platform="${key}_DOCKER_PLATFORM"
        image_var="${key}_IMAGE"
        suffix_var="${key}_TARBALL_SUFFIX"

        docker_platform="${!docker_platform}"
        image="${!image_var}"
        tarball_suffix="${!suffix_var}"

        if [[ -z "${docker_platform}" || -z "${image}" || -z "${tarball_suffix}" ]]; then
            echo "ERROR: Missing config for target ${arch}/${libc}." \
                 "Check ${config} for ${key}_DOCKER_PLATFORM, ${key}_IMAGE, ${key}_TARBALL_SUFFIX." >&2
            exit 1
        fi

        echo "========================================"
        echo "Building tarball for ${tarball_suffix}"
        echo "========================================"

        if ! docker image inspect "${image}" &>/dev/null; then
            echo "==> Pulling ${image}..."
            docker pull "${image}"
        fi

        echo "==> Starting build..."
        # -U_FORTIFY_SOURCE: suppress macro re-definition warnings when the
        # manylinux/musllinux base image already defines _FORTIFY_SOURCE at a
        # different level than CLP's CMake flags expect.
        docker run --rm \
            --platform "${docker_platform}" \
            -v "${clp_repo}:/clp" \
            -v "${output_dir}:/output" \
            -w /clp \
            -e "CORES=${cores}" \
            -e "HOST_UID=$(id -u)" \
            -e "HOST_GID=$(id -g)" \
            -e "CFLAGS=-U_FORTIFY_SOURCE" \
            -e "CXXFLAGS=-U_FORTIFY_SOURCE" \
            -e "TARBALL_SUFFIX=${tarball_suffix}" \
            "${image}" \
            bash -c '
                set -e
                git config --global --add safe.directory "*"

                echo "==> Cleaning compiler-specific build artifacts..."
                find /clp/build/deps/cpp -maxdepth 1 \
                    \( -name "cmake-settings" -o -name "*-build" -o -name "*-install" \) \
                    -exec rm -rf {} + 2>/dev/null || true
                rm -rf /clp/build/core /clp/build/codegen:*.md5 /clp/.task

                echo "==> Building dependencies..."
                CLP_CPP_MAX_PARALLELISM_PER_BUILD_TASK="${CORES}" task deps:core

                echo "==> Building core binaries..."
                CLP_CPP_MAX_PARALLELISM_PER_BUILD_TASK="${CORES}" task core

                echo "==> Bundling libraries for tarball..."
                DESTDIR=/tmp/clp-tarball-staging \
                PREFIX= \
                BIN_DIR=/clp/build/core \
                    /clp/components/core/tools/packaging/common/bundle-libs.sh

                echo "==> Creating tar.gz..."
                cd /tmp/clp-tarball-staging
                tar czf "/output/clp-s_linux_${TARBALL_SUFFIX}.tar.gz" .
                chown "${HOST_UID}:${HOST_GID}" "/output/clp-s_linux_${TARBALL_SUFFIX}.tar.gz"

                chown -R "${HOST_UID}:${HOST_GID}" /clp/build
                [ -d /clp/.task ] && chown -R "${HOST_UID}:${HOST_GID}" /clp/.task || true
            '

        echo "    Produced: ${output_dir}/clp-s_linux_${tarball_suffix}.tar.gz"
    done
done

echo ""
echo "All tarballs built:"
ls -lh "${output_dir}"/*.tar.gz
