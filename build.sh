#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pr_info() { echo -e "${GREEN}[INFO]${NC} $@"; }
pr_warn() { echo -e "${YELLOW}[WARN]${NC} $@"; }
pr_err() { echo -e "${RED}[ERROR]${NC} $@"; }
pr_step() { echo -e "${BLUE}[STEP]${NC} $@"; }

setup_toolchains() {
    pr_step "Setting up toolchains..."
    
    export ROOT_DIR=$(pwd)
    export TOOLCHAIN_DIR="$ROOT_DIR/toolchains"
    mkdir -p "$TOOLCHAIN_DIR"
    
    if [ -f "$TOOLCHAIN_DIR/clang/bin/clang" ] && [ -f "$TOOLCHAIN_DIR/gcc/bin/aarch64-linux-android-gcc" ]; then
        pr_info "Toolchains already exist, skipping download"
        export CROSS_COMPILE="$TOOLCHAIN_DIR/gcc/bin/aarch64-linux-android-"
        export PATH="$TOOLCHAIN_DIR/clang/bin:$TOOLCHAIN_DIR/gcc/bin:$PATH"
        export CLANG_TRIPLE="aarch64-linux-gnu-"
        return 0
    fi
    
    pr_info "Downloading toolchains..."
    cd "$TOOLCHAIN_DIR"
    
    CLANG_VERSION="${CLANG_VERSION:-clang-12}"
    pr_info "Using Clang: $CLANG_VERSION"
    
    case "$CLANG_VERSION" in
        "clang-12")
            pr_info "Downloading Clang 12..."
            git clone --depth=1 https://github.com/blxyzY/toolchain -b clang-12 clang
            ;;
        "neutron-clang-23")
            pr_info "Downloading Neutron Clang 23..."
            wget -q https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/26052026/neutron-clang-26052026.tar.zst -O neutron.tar.zst
            mkdir -p clang
            tar -xf neutron.tar.zst -C clang
            rm neutron.tar.zst
            ;;
        "aosp-clang-22")
            pr_info "Downloading AOSP Clang 22..."
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9b144befdfd93b90e02c663504fb9f4b95f9faf8/clang-r596125.tar.gz -O clang.tar.gz
            mkdir -p clang
            tar -xzf clang.tar.gz -C clang
            rm clang.tar.gz
            ;;
        "aosp-clang-21")
            pr_info "Downloading AOSP Clang 21..."
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/d0e0a3882edb1acc193263ae98fce706e82aca38/clang-r574158.tar.gz -O clang.tar.gz
            mkdir -p clang
            tar -xzf clang.tar.gz -C clang
            rm clang.tar.gz
            ;;
        "aosp-clang-20")
            pr_info "Downloading AOSP Clang 20..."
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz -O clang.tar.gz
            mkdir -p clang
            tar -xzf clang.tar.gz -C clang
            rm clang.tar.gz
            ;;
        "proton-clang-13")
            pr_info "Downloading Proton Clang 13..."
            git clone --depth=1 https://github.com/kdrag0n/proton-clang -b master clang
            ;;
        *)
            pr_warn "Unknown Clang version: $CLANG_VERSION, using fallback Clang 12"
            git clone --depth=1 https://github.com/blxyzY/toolchain -b clang-12 clang
            ;;
    esac
    
    if [ ! -f "clang/bin/clang" ]; then
        pr_err "Clang not found!"
        exit 1
    fi
    
    pr_info "Downloading GCC toolchain..."
    mkdir -p gcc
    
    if git clone --depth=1 https://github.com/blxyzY/toolchain -b androidcc-4.9 gcc 2>/dev/null; then
        pr_info "GCC cloned from blxyzY successfully"
    elif git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b master gcc 2>/dev/null; then
        pr_info "GCC cloned from AOSP successfully"
    else
        pr_err "Failed to clone GCC"
        exit 1
    fi
    
    cd gcc
    if [ -d "aarch64-linux-android-4.9" ]; then
        pr_info "Moving GCC from subdirectory..."
        mv aarch64-linux-android-4.9/* .
        rm -rf aarch64-linux-android-4.9
    fi
    
    if [ ! -d "bin" ]; then
        pr_err "GCC bin directory not found!"
        exit 1
    fi
    
    cd bin
    if [ ! -f "aarch64-linux-android-gcc" ]; then
        pr_warn "Creating symlink for aarch64-linux-android-gcc"
        GCC_BIN=$(ls | grep -E "aarch64-linux-android-gcc(-[0-9.]+)?" | head -1)
        if [ -n "$GCC_BIN" ] && [ "$GCC_BIN" != "aarch64-linux-android-gcc" ]; then
            ln -sf "$GCC_BIN" aarch64-linux-android-gcc
        fi
    fi
    cd ../..
    
    if [ ! -f "gcc/bin/aarch64-linux-android-gcc" ]; then
        pr_err "GCC not found after setup!"
        exit 1
    fi
    
    export CROSS_COMPILE="$TOOLCHAIN_DIR/gcc/bin/aarch64-linux-android-"
    export PATH="$TOOLCHAIN_DIR/clang/bin:$TOOLCHAIN_DIR/gcc/bin:$PATH"
    export CLANG_TRIPLE="aarch64-linux-gnu-"
    
    cd "$ROOT_DIR"
    
    pr_info "Toolchain setup complete!"
    pr_info "Clang: $(clang --version | head -1)"
    if command -v aarch64-linux-android-gcc &> /dev/null; then
        pr_info "GCC: $(aarch64-linux-android-gcc --version | head -1)"
    fi
}

setconfig() {
    if [ -d scripts ]; then
        ./scripts/config --file ./out/.config --$1 CONFIG_$2
    else
        pr_err "Scripts folder not found!"
        return 1
    fi
}

setup_ksu() {
    if [ "$KERNELSU" = "true" ]; then
        pr_step "Setting up KernelSU..."
        if [ -n "$KSU_BRANCH" ]; then
            pr_info "KernelSU branch: $KSU_BRANCH"
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s "$KSU_BRANCH"
        else
            pr_info "KernelSU branch: main (default)"
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash
        fi
    else
        pr_info "KernelSU disabled"
    fi
}

get_ksu_version() {
    if [ -d "KernelSU" ] && [ "$KERNELSU" = "true" ]; then
        KSU_REV_COUNT=$(cd KernelSU && git rev-list --count HEAD 2>/dev/null || echo "0")
        KSU_VERSION=$(expr 10200 + $KSU_REV_COUNT 2>/dev/null || echo "10200")
        echo "$KSU_VERSION"
    else
        echo "0"
    fi
}

build_kernel() {
    pr_step "Starting kernel build..."
    
    export ARCH=arm64
    export LLVM=1
    export LLVM_IAS=1
    export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-xlvy}"
    export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-xlvy_10}"
    
    mkdir -p out
    
    MAKE_ARGS="O=out ARCH=arm64 LLVM=1 LLVM_IAS=1"
    MAKE_ARGS="$MAKE_ARGS -j$JOB_COUNT"
    
    if command -v clang &> /dev/null; then
        MAKE_ARGS="$MAKE_ARGS CC=clang"
    else
        pr_err "Clang not found!"
        exit 1
    fi
    
    if command -v aarch64-linux-android-gcc &> /dev/null; then
        MAKE_ARGS="$MAKE_ARGS CROSS_COMPILE=$CROSS_COMPILE"
    else
        pr_warn "GCC not found, using Clang for cross compilation"
        MAKE_ARGS="$MAKE_ARGS CROSS_COMPILE=llvm-"
    fi
    
    MAKE_ARGS="$MAKE_ARGS CLANG_TRIPLE=$CLANG_TRIPLE"
    MAKE_ARGS="$MAKE_ARGS CONFIG_BUILD_ARM64_DT_OVERLAY=y"
    MAKE_ARGS="$MAKE_ARGS CONFIG_SECTION_MISMATCH_WARN_ONLY=y"
    MAKE_ARGS="$MAKE_ARGS CONFIG_NO_ERROR_ON_MISMATCH=y"
    
    if [ -n "$KCFLAGS" ]; then
        MAKE_ARGS="$MAKE_ARGS KCFLAGS=$KCFLAGS"
    fi
    
    pr_step "Generating defconfig: $DEFCONFIG"
    make $MAKE_ARGS $DEFCONFIG
    
    if [ ! -f "out/.config" ]; then
        pr_err "Failed to generate defconfig"
        exit 1
    fi
    
    if [ "$KERNELSU" = "true" ]; then
        pr_step "Enabling KernelSU in config"
        setconfig enable KSU
    fi
    
    pr_step "Configuring LTO: ${LTO:-none}"
    case "${LTO:-none}" in
        "thin")
            setconfig disable LTO_NONE
            setconfig enable LTO
            setconfig enable THINLTO
            setconfig enable LTO_CLANG
            setconfig enable ARCH_SUPPORTS_LTO_CLANG
            setconfig enable ARCH_SUPPORTS_THINLTO
            ;;
        "full")
            setconfig disable LTO_NONE
            setconfig enable LTO
            setconfig disable THINLTO
            setconfig enable LTO_CLANG
            setconfig enable ARCH_SUPPORTS_LTO_CLANG
            setconfig enable ARCH_SUPPORTS_THINLTO
            ;;
        *)
            setconfig enable LTO_NONE
            setconfig disable LTO
            setconfig disable THINLTO
            setconfig disable LTO_CLANG
            setconfig enable ARCH_SUPPORTS_LTO_CLANG
            setconfig enable ARCH_SUPPORTS_THINLTO
            ;;
    esac
    
    if [ "$SELINUX_PERMISSIVE" = "true" ]; then
        pr_step "Setting SELinux permissive"
        if [ -d "security/selinux" ]; then
            rm -rf security/selinux
        fi
        cd security/
        git clone --depth=1 https://github.com/xlvy/selinux_perm.git selinux
        rm -rf selinux/.git
        cd ..
        echo "CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE=y" >> out/.config
    fi
    
    pr_step "Compiling kernel with $JOB_COUNT jobs..."
    make $MAKE_ARGS
    
    IMAGE="out/arch/arm64/boot/Image"
    if [ -f "$IMAGE" ]; then
        pr_info "Kernel built successfully!"
        pr_info "Image: $IMAGE"
        return 0
    else
        pr_err "Kernel build failed!"
        pr_err "Image not found: $IMAGE"
        return 1
    fi
}

post_build() {
    pr_step "Post-build processing..."
    
    KERNEL_VER=$(make kernelversion 2>/dev/null || echo "unknown")
    GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
    BUILD_DATE=$(date +'%Y%m%d%H%M%S')
    
    # Get KernelSU version
    KSU_VERSION=$(get_ksu_version)
    
    cat > out/build_details.txt << EOF
Kernel Version: $KERNEL_VER
Git SHA: $GIT_SHA
Build Date: $(date)
Defconfig: $DEFCONFIG
LTO: ${LTO:-none}
KernelSU: ${KERNELSU:-false}
KSU Version: $KSU_VERSION
KSU Branch: ${KSU_BRANCH:-N/A}
SELinux: ${SELINUX_STATE:-Enforcing}
Clang: $(clang --version | head -1)
GCC: $(aarch64-linux-android-gcc --version 2>/dev/null | head -1 || echo "Using Clang")
EOF
    
    cp out/.config out/build_config.txt
    
    if [ ! -d "AnyKernel3" ]; then
        pr_err "AnyKernel3 folder not found!"
        exit 1
    fi
    
    pr_step "Creating AnyKernel3 zip..."
    
    if [ -f "out/arch/arm64/boot/Image" ]; then
        cp out/arch/arm64/boot/Image AnyKernel3/
        pr_info "Image copied to AnyKernel3"
    else
        pr_err "Image not found!"
        return 1
    fi
    
    if [ "${QCA_IS_MODULE:-false}" = "true" ]; then
        pr_info "Including modules..."
        if [ -f "AnyKernel3/anykernel.sh" ]; then
            sed -i 's/do.modules=.*/do.modules=1/' AnyKernel3/anykernel.sh
        fi
        mkdir -p AnyKernel3/modules/vendor/lib/modules
        if [ -f "out/drivers/staging/qcacld-3.0/wlan.ko" ]; then
            llvm-strip out/drivers/staging/qcacld-3.0/wlan.ko --strip-unneeded 2>/dev/null
            cp out/drivers/staging/qcacld-3.0/wlan.ko AnyKernel3/modules/vendor/lib/modules/
        fi
    fi
    
    cat > utsrelease.c << 'EOF'
#include <stdio.h>
#include "out/include/generated/utsrelease.h"

int main() {
    printf("%s\n", UTS_RELEASE);
    return 0;
}
EOF
    
    gcc -CC utsrelease.c -o getutsrel 2>/dev/null
    if [ -f "./getutsrel" ]; then
        UTSRELEASE=$(./getutsrel)
        if [ -f "AnyKernel3/anykernel.sh" ]; then
            sed -i "s/kernel\.string=.*/kernel.string=$UTSRELEASE/" AnyKernel3/anykernel.sh
            pr_info "Updated kernel.string to: $UTSRELEASE"
        fi
    fi
    
    cd AnyKernel3
    ZIP_NAME="AnyKernel3-${KERNEL_VER}_${GIT_SHA}-${BUILD_DATE}.zip"
    zip -r9 ../$ZIP_NAME * -x .git README.md .gitignore
    cd ..
    
    pr_info "Zip created: $ZIP_NAME"
    echo "ZIP_FILE=$(pwd)/$ZIP_NAME"
    echo "ZIP_NAME=$ZIP_NAME" >> $GITHUB_ENV 2>/dev/null || true
    
    # Save all build info to GITHUB_ENV
    echo "KERNEL_VER=$KERNEL_VER" >> $GITHUB_ENV 2>/dev/null || true
    echo "GIT_SHA=$GIT_SHA" >> $GITHUB_ENV 2>/dev/null || true
    echo "BUILD_DATE=$BUILD_DATE" >> $GITHUB_ENV 2>/dev/null || true
    echo "KERNELSU=${KERNELSU:-false}" >> $GITHUB_ENV 2>/dev/null || true
    echo "KSU_VERSION=$KSU_VERSION" >> $GITHUB_ENV 2>/dev/null || true
    echo "KSU_BRANCH=${KSU_BRANCH:-N/A}" >> $GITHUB_ENV 2>/dev/null || true
    echo "LTO=${LTO:-none}" >> $GITHUB_ENV 2>/dev/null || true
    echo "SELINUX_STATE=${SELINUX_STATE:-Enforcing}" >> $GITHUB_ENV 2>/dev/null || true
    echo "CLANG_VER=$(clang --version | head -1)" >> $GITHUB_ENV 2>/dev/null || true
}

usage() {
    cat << EOF
Usage: $0 <target> <jobs> <defconfig>

Targets:
    kernel      - Build kernel
    defconfig   - Generate defconfig only
    clean       - Clean build

Jobs:
    -j <number> or --jobs <number>

Environment Variables:
    LTO - none, thin, full (default: none)
    KERNELSU - true/false (default: false)
    KSU_BRANCH - KernelSU branch (default: main)
    SELINUX_PERMISSIVE - true/false (default: false)
    CLANG_VERSION - clang-12, neutron-clang-23, aosp-clang-20/21/22, proton-clang-13
    KBUILD_BUILD_USER - Build user (default: xlvy)
    KBUILD_BUILD_HOST - Build host (default: xlvy_10)
    KCFLAGS - Additional compiler flags

Example:
    $0 kernel -j 8 a23_eur_open_defconfig
    KERNELSU=true KSU_BRANCH=main $0 kernel -j 8 a23_eur_open_defconfig
    LTO=thin SELINUX_PERMISSIVE=true $0 kernel -j 8 a23_eur_open_defconfig
EOF
    exit 1
}

if [ $# -lt 3 ]; then
    pr_err "Invalid arguments!"
    usage
fi

BUILD_TARGET="$1"
JOB_FLAG="$2"
JOB_COUNT="$3"
DEFCONFIG="${4:-a23_eur_open_defconfig}"

if [ "$BUILD_TARGET" = "clean" ]; then
    pr_step "Cleaning..."
    rm -rf out toolchains 2>/dev/null
    rm -f *.zip 2>/dev/null
    make clean 2>/dev/null
    make mrproper 2>/dev/null
    pr_info "Clean complete!"
    exit 0
fi

if [ "$JOB_FLAG" != "-j" ] && [ "$JOB_FLAG" != "--jobs" ]; then
    pr_err "Invalid job flag: $JOB_FLAG"
    usage
fi

if ! [[ "$JOB_COUNT" =~ ^[0-9]+$ ]]; then
    pr_err "Invalid job count: $JOB_COUNT"
    usage
fi

if [ "$BUILD_TARGET" != "kernel" ] && [ "$BUILD_TARGET" != "defconfig" ]; then
    pr_err "Invalid target: $BUILD_TARGET"
    usage
fi

pr_info "=== Solstice Kernel Builder ==="
pr_info "Target: $BUILD_TARGET"
pr_info "Defconfig: $DEFCONFIG"
pr_info "Jobs: $JOB_COUNT"
pr_info "LTO: ${LTO:-none}"
pr_info "KernelSU: ${KERNELSU:-false}"
pr_info "SELinux: ${SELINUX_STATE:-Enforcing}"

setup_toolchains
setup_ksu

if [ "$BUILD_TARGET" = "defconfig" ]; then
    pr_step "Generating defconfig only..."
    mkdir -p out
    make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
        CROSS_COMPILE=$CROSS_COMPILE CLANG_TRIPLE=$CLANG_TRIPLE \
        -j$JOB_COUNT $DEFCONFIG
    
    if [ -f "out/.config" ]; then
        cp out/.config out/build_config.txt
        pr_info "Defconfig generated: out/.config"
    else
        pr_err "Failed to generate defconfig"
        exit 1
    fi
else
    if build_kernel; then
        post_build
        pr_info "Build completed successfully!"
        pr_info "Output: $(ls *.zip 2>/dev/null)"
    else
        pr_err "Build failed!"
        exit 1
    fi
fi
