#!/usr/bin/env sh

# Checks that libc builds properly for all supported targets on a particular
# Rust version:
# The FILTER environment variable can be used to select which target(s) to build.
# For example: set FILTER to vxworks to select the targets that has vxworks in name

set -ex

: "${TOOLCHAIN?The TOOLCHAIN environment variable must be set.}"
: "${OS?The OS environment variable must be set.}"

RUST=${TOOLCHAIN}
VERBOSE=-v

echo "Testing Rust ${RUST} on ${OS}"

if [ "${TOOLCHAIN}" = "nightly" ] ; then
    rustup component add rust-src
fi

test_target() {
    BUILD_CMD="${1}"
    TARGET="${2}"
    NO_STD="${3}"

    # If there is a std component, fetch it:
    if [ "${NO_STD}" != "1" ]; then
        # FIXME: rustup often fails to download some artifacts due to network
        # issues, so we retry this N times.
        N=5
        n=0
        until [ $n -ge $N ]
        do
            if rustup target add "${TARGET}" --toolchain "${RUST}" ; then
                break
            fi
            n=$((n+1))
            sleep 1
        done
    fi

    # Test that libc builds without any default features (no std)
    if [ "${NO_STD}" != "1" ]; then
        cargo "+${RUST}" "${BUILD_CMD}" "$VERBOSE" --no-default-features --target "${TARGET}"
    else
        # FIXME: With `build-std` feature, `compiler_builtins` emits a lof of lint warnings.
        RUSTFLAGS="-A improper_ctypes_definitions" cargo "+${RUST}" "${BUILD_CMD}" \
            -Z build-std=core,alloc "$VERBOSE" --no-default-features --target "${TARGET}"
    fi
    # Test that libc builds with default features (e.g. std)
    # if the target supports std
    if [ "$NO_STD" != "1" ]; then
        cargo "+${RUST}" "${BUILD_CMD}" "$VERBOSE" --target "${TARGET}"
    else
        RUSTFLAGS="-A improper_ctypes_definitions" cargo "+${RUST}" "${BUILD_CMD}" \
            -Z build-std=core,alloc "$VERBOSE" --target "${TARGET}"
    fi

    # Test that libc builds with the `extra_traits` feature
    if [ "${NO_STD}" != "1" ]; then
        cargo "+${RUST}" "${BUILD_CMD}" "$VERBOSE" --no-default-features --target "${TARGET}" \
            --features extra_traits
    else
        RUSTFLAGS="-A improper_ctypes_definitions" cargo "+${RUST}" "${BUILD_CMD}" \
            -Z build-std=core,alloc "$VERBOSE" --no-default-features \
            --target "${TARGET}" --features extra_traits
    fi

    # Test the 'const-extern-fn' feature on nightly
    if [ "${RUST}" = "nightly" ]; then
        if [ "${NO_STD}" != "1" ]; then
            cargo "+${RUST}" "${BUILD_CMD}" "$VERBOSE" --no-default-features --target "${TARGET}" \
                --features const-extern-fn
        else
            RUSTFLAGS="-A improper_ctypes_definitions" cargo "+${RUST}" "${BUILD_CMD}" \
                -Z build-std=core,alloc "$VERBOSE" --no-default-features \
                --target "${TARGET}" --features const-extern-fn
        fi
    fi

    # Also test that it builds with `extra_traits` and default features:
    if [ "$NO_STD" != "1" ]; then
        cargo "+${RUST}" "${BUILD_CMD}" "$VERBOSE" --target "${TARGET}" \
            --features extra_traits
    else
        RUSTFLAGS="-A improper_ctypes_definitions" cargo "+${RUST}" "${BUILD_CMD}" \
            -Z build-std=core,alloc "$VERBOSE" --target "${TARGET}" \
            --features extra_traits
    fi
}

# Targets which are not available via rustup and must be built with -Zbuild-std
RUST_LINUX_NO_CORE_TARGETS="\
x86_64-unknown-openbsd
aarch64-pc-windows-msvc \
aarch64-unknown-freebsd \
"

if [ "${RUST}" = "nightly" ] && [ "${OS}" = "linux" ]; then
    for TARGET in $RUST_LINUX_NO_CORE_TARGETS; do
        if echo "$TARGET"|grep -q "$FILTER"; then
            test_target build "$TARGET" 1
        fi
    done
fi

RUST_APPLE_NO_CORE_TARGETS="\
armv7s-apple-ios \
i686-apple-darwin \
i386-apple-ios \
"

if [ "${RUST}" = "nightly" ] && [ "${OS}" = "macos" ]; then
    for TARGET in $RUST_APPLE_NO_CORE_TARGETS; do
        if echo "$TARGET" | grep -q "$FILTER"; then
            test_target build "$TARGET" 1
        fi
    done
fi
