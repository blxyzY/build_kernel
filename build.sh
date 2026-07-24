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
            git clone --depth=1 https://github.com/blxyzY/toolchain -b clang-12 clang
            ;;
        "neutron-clang-23")
            wget -q https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/26052026/neutron-clang-26052026.tar.zst -O neutron.tar.zst
            mkdir -p clang && tar -xf neutron.tar.zst -C clang && rm neutron.tar.zst
            ;;
        "aosp-clang-22")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9b144befdfd93b90e02c663504fb9f4b95f9faf8/clang-r596125.tar.gz -O clang.tar.gz
            mkdir -p clang && tar -xzf clang.tar.gz -C clang && rm clang.tar.gz
            ;;
        "aosp-clang-21")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/d0e0a3882edb1acc193263ae98fce706e82aca38/clang-r574158.tar.gz -O clang.tar.gz
            mkdir -p clang && tar -xzf clang.tar.gz -C clang && rm clang.tar.gz
            ;;
        "aosp-clang-20")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz -O clang.tar.gz
            mkdir -p clang && tar -xzf clang.tar.gz -C clang && rm clang.tar.gz
            ;;
        "proton-clang-13")
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
    
    if ! git clone --depth=1 https://github.com/blxyzY/toolchain -b androidcc-4.9 gcc 2>/dev/null; then
        if ! git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b master gcc 2>/dev/null; then
            pr_err "Failed to clone GCC"
            exit 1
        fi
    fi
    
    cd gcc
    [ -d "aarch64-linux-android-4.9" ] && mv aarch64-linux-android-4.9/* . && rm -rf aarch64-linux-android-4.9
    
    if [ ! -d "bin" ]; then
        pr_err "GCC bin directory not found!"
        exit 1
    fi
    
    cd bin
    if [ ! -f "aarch64-linux-android-gcc" ]; then
        pr_warn "Creating symlink for aarch64-linux-android-gcc"
        GCC_BIN=$(ls | grep -E "aarch64-linux-android-gcc(-[0-9.]+)?" | head -1)
        [ -n "$GCC_BIN" ] && [ "$GCC_BIN" != "aarch64-linux-android-gcc" ] && ln -sf "$GCC_BIN" aarch64-linux-android-gcc
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
    command -v aarch64-linux-android-gcc &> /dev/null && pr_info "GCC: $(aarch64-linux-android-gcc --version | head -1)"
}

setconfig() {
    [ ! -d scripts ] && pr_err "Scripts folder not found!" && return 1
    ./scripts/config --file ./out/.config --$1 CONFIG_$2
}

setup_ksu() {
    [ "$KERNELSU" != "true" ] && pr_info "KernelSU disabled" && return 0
    
    pr_step "Setting up KernelSU..."
    local branch=${KSU_BRANCH:-main}
    pr_info "KernelSU branch: $branch"
    curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s "$branch"
}

get_ksu_version() {
    if [ -d "KernelSU" ] && [ "$KERNELSU" = "true" ]; then
        local count=$(cd KernelSU && git rev-list --count HEAD 2>/dev/null || echo "0")
        echo $((10200 + count))
    else
        echo "0"
    fi
}

get_changelog() {
    if [ -d ".git" ]; then
        git log -5 --pretty=format:"• %s" 2>/dev/null || echo "• No changelog available"
    else
        echo "• No changelog available"
    fi
}

configure_selinux() {
    local defconfig_path="arch/arm64/configs/$DEFCONFIG"
    
    if [ ! -f "$defconfig_path" ]; then
        pr_err "Defconfig file not found: $defconfig_path"
        return 1
    fi
    
    if [ "$SELINUX_PERMISSIVE" = "true" ]; then
        pr_step "Configuring SELinux to Permissive..."

        sed -i 's/CONFIG_CMDLINE=".*"/CONFIG_CMDLINE="androidboot.selinux=permissive"/' "$defconfig_path"
        sed -i 's/# CONFIG_SECURITY_SELINUX_DEVELOP is not set/CONFIG_SECURITY_SELINUX_DEVELOP=y/' "$defconfig_path"
        sed -i 's/CONFIG_SECURITY_SELINUX_ALWAYS_ENFORCE=y/# CONFIG_SECURITY_SELINUX_ALWAYS_ENFORCE is not set/' "$defconfig_path" 2>/dev/null || true
        if grep -q "CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE" "$defconfig_path"; then
            sed -i 's/# CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE is not set/CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE=y/' "$defconfig_path"
        else
            echo "CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE=y" >> "$defconfig_path"
        fi
        sed -i 's/CONFIG_INTEGRITY=y/# CONFIG_INTEGRITY is not set/' "$defconfig_path"
        sed -i 's/CONFIG_SECURITY_DEFEX=y/# CONFIG_SECURITY_DEFEX is not set/' "$defconfig_path"
        sed -i 's/CONFIG_PROCA=y/# CONFIG_PROCA is not set/' "$defconfig_path"
        sed -i 's/CONFIG_FIVE=y/# CONFIG_FIVE is not set/' "$defconfig_path"
        pr_info "SELinux set to Permissive"
    else
        pr_step "Configuring SELinux to Enforcing..."
        sed -i 's/CONFIG_CMDLINE="androidboot.selinux=permissive"/CONFIG_CMDLINE=""/' "$defconfig_path"
        sed -i 's/CONFIG_SECURITY_SELINUX_DEVELOP=y/# CONFIG_SECURITY_SELINUX_DEVELOP is not set/' "$defconfig_path"
        sed -i 's/CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE=y/# CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE is not set/' "$defconfig_path"
        pr_info "SELinux set to Enforcing"
    fi
}

build_kernel() {
    pr_step "Starting kernel build..."
    
    export ARCH=arm64 LLVM=1 LLVM_IAS=1
    export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-xlvy}"
    export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-xlvy_lab}"
    
    mkdir -p out
    configure_selinux
    
    MAKE_ARGS="O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang -j$JOB_COUNT"
    MAKE_ARGS="$MAKE_ARGS CROSS_COMPILE=${CROSS_COMPILE:-llvm-}"
    MAKE_ARGS="$MAKE_ARGS CLANG_TRIPLE=${CLANG_TRIPLE:-aarch64-linux-gnu-}"
    MAKE_ARGS="$MAKE_ARGS CONFIG_BUILD_ARM64_DT_OVERLAY=y CONFIG_SECTION_MISMATCH_WARN_ONLY=y CONFIG_NO_ERROR_ON_MISMATCH=y"
    [ -n "$KCFLAGS" ] && MAKE_ARGS="$MAKE_ARGS KCFLAGS=$KCFLAGS"
    
    pr_step "Generating defconfig: $DEFCONFIG"
    make $MAKE_ARGS $DEFCONFIG
    
    [ ! -f "out/.config" ] && pr_err "Failed to generate defconfig" && exit 1
    
    [ "$KERNELSU" = "true" ] && { pr_step "Enabling KernelSU in config"; setconfig enable KSU; }
    
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
    
    pr_step "Compiling kernel with $JOB_COUNT jobs..."
    make $MAKE_ARGS
    
    IMAGE="out/arch/arm64/boot/Image"
    if [ -f "$IMAGE" ]; then
        pr_info "Kernel built successfully! Image: $IMAGE"
        return 0
    else
        pr_err "Kernel build failed! Image not found: $IMAGE"
        return 1
    fi
}

post_build() {
    pr_step "Post-build processing..."
    
    local KERNEL_VER=$(make kernelversion 2>/dev/null || echo "unknown")
    local GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
    local BUILD_DATE=$(date +'%Y%m%d%H%M%S')
    local KSU_VERSION=$(get_ksu_version)
    local CHANGELOG=$(get_changelog)

    if [ -n "$BUILD_TIME" ]; then
        echo "BUILD_TIME=$BUILD_TIME" >> $GITHUB_ENV 2>/dev/null || true
    fi
    
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

Changelog:
$CHANGELOG
EOF
    
    cp out/.config out/build_config.txt
    
    [ ! -d "AnyKernel3" ] && pr_err "AnyKernel3 folder not found!" && exit 1
    
    pr_step "Creating AnyKernel3 zip..."
    
    [ -f "out/arch/arm64/boot/Image" ] && cp out/arch/arm64/boot/Image AnyKernel3/ || { pr_err "Image not found!"; return 1; }

    if [ "${QCA_IS_MODULE:-false}" = "true" ]; then
        pr_info "Including modules..."
        [ -f "AnyKernel3/anykernel.sh" ] && sed -i 's/do.modules=.*/do.modules=1/' AnyKernel3/anykernel.sh
        mkdir -p AnyKernel3/modules/vendor/lib/modules
        if [ -f "out/drivers/staging/qcacld-3.0/wlan.ko" ]; then
            llvm-strip out/drivers/staging/qcacld-3.0/wlan.ko --strip-unneeded 2>/dev/null
            cp out/drivers/staging/qcacld-3.0/wlan.ko AnyKernel3/modules/vendor/lib/modules/
        fi
    fi

    cat > utsrelease.c << 'EOF'
#include <stdio.h>
#include "out/include/generated/utsrelease.h"
int main() { printf("%s\n", UTS_RELEASE); return 0; }
EOF
    
    if gcc -CC utsrelease.c -o getutsrel 2>/dev/null && [ -f "./getutsrel" ]; then
        UTSRELEASE=$(./getutsrel)
        [ -f "AnyKernel3/anykernel.sh" ] && sed -i "s/kernel\.string=.*/kernel.string=$UTSRELEASE/" AnyKernel3/anykernel.sh
        pr_info "Updated kernel.string to: $UTSRELEASE"
    fi
    
    # Create zip
    cd AnyKernel3
    ZIP_NAME="AnyKernel3-${KERNEL_VER}_${GIT_SHA}-${BUILD_DATE}.zip"
    zip -r9 ../$ZIP_NAME * -x .git README.md .gitignore
    cd ..
    
    pr_info "Zip created: $ZIP_NAME"

    for var in KERNEL_VER GIT_SHA BUILD_DATE KERNELSU KSU_VERSION KSU_BRANCH LTO SELINUX_STATE; do
        eval "value=\$${var}"
        [ -n "$value" ] && echo "$var=$value" >> $GITHUB_ENV 2>/dev/null || true
    done
    echo "ZIP_FILE=$(pwd)/$ZIP_NAME" >> $GITHUB_ENV 2>/dev/null || true
    echo "ZIP_NAME=$ZIP_NAME" >> $GITHUB_ENV 2>/dev/null || true
    echo "CLANG_VER=$(clang --version | head -1)" >> $GITHUB_ENV 2>/dev/null || true
    
    echo "$CHANGELOG" > changelog.txt
}

usage() {
    cat << EOF
Usage: $0 <target> <jobs> <defconfig>

Targets:
    kernel      - Build kernel
    defconfig   - Generate defconfig only
    clean       - Clean build

Jobs: -j <number> or --jobs <number>

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

[ $# -lt 3 ] && pr_err "Invalid arguments!" && usage

BUILD_TARGET="$1"
JOB_FLAG="$2"
JOB_COUNT="$3"
DEFCONFIG="${4:-a23_eur_open_defconfig}"

if [ "$BUILD_TARGET" = "clean" ]; then
    pr_step "Cleaning..."
    rm -rf out toolchains *.zip 2>/dev/null
    make clean mrproper 2>/dev/null
    pr_info "Clean complete!"
    exit 0
fi

if [[ "$JOB_FLAG" != "-j" && "$JOB_FLAG" != "--jobs" ]] || ! [[ "$JOB_COUNT" =~ ^[0-9]+$ ]]; then
    pr_err "Invalid job flag or count"
    usage
fi

[[ "$BUILD_TARGET" != "kernel" && "$BUILD_TARGET" != "defconfig" ]] && pr_err "Invalid target: $BUILD_TARGET" && usage

pr_info "=== Solstice Kernel Builder ==="
pr_info "Target: $BUILD_TARGET | Defconfig: $DEFCONFIG | Jobs: $JOB_COUNT"
pr_info "LTO: ${LTO:-none} | KernelSU: ${KERNELSU:-false} | SELinux: ${SELINUX_STATE:-Enforcing}"

setup_toolchains
setup_ksu

if [ "$BUILD_TARGET" = "defconfig" ]; then
    pr_step "Generating defconfig only..."
    mkdir -p out
    make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
        CROSS_COMPILE=${CROSS_COMPILE:-llvm-} \
        CLANG_TRIPLE=${CLANG_TRIPLE:-aarch64-linux-gnu-} \
        -j$JOB_COUNT $DEFCONFIG
    
    if [ -f "out/.config" ]; then
        cp out/.config out/build_config.txt
        pr_info "Defconfig generated: out/.config"
    else
        pr_err "Failed to generate defconfig"
        exit 1
    fi
else
    if build_kernel && post_build; then
        pr_info "Build completed successfully!"
        pr_info "Output: $(ls *.zip 2>/dev/null)"
    else
        pr_err "Build failed!"
        exit 1
    fi
fi

