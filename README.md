# 🔧 Build Kernel Action - a23

GitHub Actions workflow for building Samsung Galaxy A23 4G (a23q) kernel.

## 🚀 Usage

1. Go to **Actions** → **Build Kernel** → **Run workflow**
2. Fill parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| REPO_URL | Kernel repo URL | `blxyzY/android_kernel_samsung_sm6225` |
| DEFCONFIG | Defconfig name | `a23q-perf_defconfig` |
| BRANCH | Kernel branch | `lineage-21` |
| LTO | Link Time Optimization | `none` / `thin` |
| CLANG_VERSION | Clang version | `neutron-clang-23` |
| KBUILD_USER | Builder name | `xlvy` |
| SETUP_KSU | Enable KernelSU | `true` / `false` |
| KSU_BRANCH | KernelSU branch | `main` |
| UPLOAD_TO_TG | Upload to Telegram | `true` / `false` |

## 📦 Output

| Artifact | Description |
|----------|-------------|
| `AnyKernel3-*.zip` | Flashable ZIP |
| `BuildDetails-*.zip` | Build logs & config |

## 📱 Device

| Device | Codename |
|--------|----------|
| Samsung Galaxy A23 4G | a23q |

## 🔧 Defconfig

```bash
a23q-perf_defconfig
