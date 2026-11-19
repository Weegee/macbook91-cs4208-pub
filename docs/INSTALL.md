# Installing and removing the package

For Arch Linux and derivatives. The short form is in the README.

Requirements: `base-devel`, `dkms`, the headers of every kernel you use and,
for kernels built with clang (CachyOS), `clang`, `lld` and `llvm`. The build
refuses to run if the toolchain family does not match the kernel's, rather than
producing a module that loads and misbehaves.

1. Open the [latest release](https://github.com/Weegee/macbook91-cs4208-pub/releases/latest)
   and download `PKGBUILD`, `macbook91-cs4208.install`, the source tarball
   `macbook91-cs4208-dkms-VERSION.tar` and `SHA256SUMS` into one new
   directory. VERSION is the release's version, for example `20261102.01`.
2. In that directory, check the files:

   ```bash
   sha256sum -c --ignore-missing SHA256SUMS
   ```

   The output lists three files, each with `OK`:

   ```text
   PKGBUILD: OK
   macbook91-cs4208.install: OK
   macbook91-cs4208-dkms-VERSION.tar: OK
   ```

3. Build and install the package:

   ```bash
   makepkg -si
   ```

4. Reboot.
5. Check the installation in a terminal and answer the listening checks when
   it asks:

   ```bash
   macbook91-audio-verify
   ```

`--ignore-missing` skips the lines of `SHA256SUMS` whose files you did not
download (`.SRCINFO`, `STATUS.txt`, `upstream.lock`, or any of the three files
above). It fails when none of the listed files is there, but it exits
successfully as soon as one of them is, so the exit status alone does not show
that the three files were checked: look for the three `OK` lines.
`macbook91-audio-verify --help` lists the verifier's options; `--no-sound` runs
the software checks only and plays and records nothing.

To undo the installation, remove the package and reboot; the stock in-tree
codec is back:

```bash
sudo pacman -R macbook91-cs4208-dkms
```

Checked on 2026-11-09: step 2, on the files of release 20261102.01. Not run
for this revision of the text: steps 3 to 5 and the removal. What has run on
hardware, release by release, is under "What is proven, and what is not".

No built package is attached to this release; build it with `makepkg` as
above. If a later release lists a ready-built package, install that with
`sudo pacman -U` instead. Packages are not signed. If you maintain your own
pacman repository, add the package to it as usual.
