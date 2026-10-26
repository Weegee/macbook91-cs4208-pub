# namcap results for `macbook91-cs4208-dkms`

Measured 2026-10-26 on `macbook91-cs4208-dkms` 20261026.01-1, built from this
tree with `make arch-pkg`:

    namcap dist/macbook91-cs4208-dkms-20261026.01-1-x86_64.pkg.tar.zst
    namcap packaging/arch/PKGBUILD

The PKGBUILD check prints nothing. The package check reports **0 errors** and
five warnings, all expected for a DKMS source package; each is explained here
rather than silenced.

| Warning | Why it is correct to leave |
| --- | --- |
| `No ELF files and not an "any" package` | The package ships *sources*; the module is compiled by DKMS at install time. `arch=('x86_64')` is kept deliberately: this driver targets one Intel machine (MacBook9,1), so `any` would advertise architectures it cannot serve. Arch's own `*-dkms` packages do the same. |
| `Dependency bash detected and implicitly satisfied` | `/usr/bin/macbook91-audio-verify` and `/usr/lib/macbook91-cs4208/kernel-series` (with its copy in the DKMS source tree) are bash scripts, and `bash` is in `base`; Arch packaging convention is not to depend on it explicitly. |
| `Dependency included, but may not be needed ('dkms')` | namcap only inspects shipped files. `dkms` is what builds and installs the module. |
| `Dependency included, but may not be needed ('wireplumber')` | Required: this speaker path has no hardware volume control, so without the shipped software-volume configuration the desktop slider does nothing and output is always full scale. The WirePlumber drop-in this package installs also selects the ACP profile set without which a plugged headphone jack leaves this card with no sink. namcap cannot see that a configuration file needs the program that reads it. |
| `Dependency included, but may not be needed ('linux-cachyos-lts-headers')` | Required: DKMS builds only for a kernel whose headers are installed, and the CachyOS LTS kernel is the package's supported default; the headers package pulls in `linux-cachyos-lts` itself. namcap cannot see that DKMS needs a kernel's build tree. |

clang, lld and llvm are not named at all: the build takes the compiler family
from the target kernel's own `.config`, the GCC of the LTS kernel comes with
`dkms`, and `linux-cachyos-headers`, the headers of the clang-built current
kernel, depends on clang, lld and llvm itself (`packaging/arch/PKGBUILD`).
