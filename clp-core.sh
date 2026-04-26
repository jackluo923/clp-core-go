CLP_REPO="y-scope/clp"
# Branch name, tag, or commit SHA to build clp-s from.
# A moving branch name is convenient but not reproducible across builds.
# Pin to a tag or commit SHA for reproducible builds.
CLP_REF="timestamp-compatibility-snapshot"

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
