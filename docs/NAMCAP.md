# namcap results for `macbook91-cs4208-dkms`

Measured 2026-10-15 on `macbook91-cs4208-dkms` 20261006.01-1, built from this
tree with `make arch-pkg`:

    namcap dist/macbook91-cs4208-dkms-20261006.01-1-x86_64.pkg.tar.zst
    namcap packaging/arch/PKGBUILD

The PKGBUILD check prints nothing. The package check reports **0 errors** and
four warnings, all expected for a DKMS source package; each is explained here
rather than silenced.

| Warning | Why it is correct to leave |
| --- | --- |
| `No ELF files and not an "any" package` | The package ships *sources*; the module is compiled by DKMS at install time. `arch=('x86_64')` is kept deliberately: this driver targets one Intel machine (MacBook9,1), so `any` would advertise architectures it cannot serve. Arch's own `*-dkms` packages do the same. |
| `Dependency bash detected and implicitly satisfied` | `/usr/bin/macbook91-audio-verify` is a bash script, and `bash` is in `base`; Arch packaging convention is not to depend on it explicitly. |
| `Dependency included, but may not be needed ('dkms')` | namcap only inspects shipped files. `dkms` is what builds and installs the module. |
| `Dependency included, but may not be needed ('wireplumber')` | Required: this speaker path has no hardware volume control, so without the shipped software-volume configuration the desktop slider does nothing and output is always full scale. The WirePlumber drop-in this package installs also selects the ACP profile set without which a plugged headphone jack leaves this card with no sink. namcap cannot see that a configuration file needs the program that reads it. |

clang, lld and llvm are `optdepends`, not dependencies: the build
takes the compiler family from the target kernel's own `.config`, and the
install scriptlet names the missing compiler and the command that installs it
(`packaging/arch/PKGBUILD`).
