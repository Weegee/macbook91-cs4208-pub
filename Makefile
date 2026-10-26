# SPDX-License-Identifier: GPL-3.0-or-later
# Package targets. Run from the repository root; the module itself is built
# by src/cs420x-a1534/Makefile (DKMS), not here.
#
#   make dist            assemble the upstream-derived sources at the newest kernel
#                        tag of each series in packaging/upstream.lock, then write the
#                        reproducible source tarball dist/NAME-VERSION.tar
#   make install         what the package installs; packaging/arch/PKGBUILD's
#                        package() is exactly `make PREFIX=/usr DESTDIR="$pkgdir"
#                        install`, run from that tarball
#   make srcinfo         regenerate packaging/arch/.SRCINFO
#   make arch-pkg        release build: the tarball's SHA256 must be the one
#                        pinned in packaging/arch/PKGBUILD
#   make arch-pkg-dev    build of an unreleased tree: tracked files as they are
#                        on disk, the pin replaced in the build copy only
#
# Packages are built in build/arch and copied to dist/. FETCH_ARGS overrides
# the fetcher's options (default: the lockfile's tags); MAKEPKG_FLAGS passes
# options to makepkg (e.g. --syncdeps in CI).

NAME := macbook91-cs4208-dkms
# The runtime identity, which deliberately did not move when the package was
# renamed: DKMS module, /usr/src directory and data paths (see the PKGBUILD).
MODNAME := macbook91-cs4208
VERSION := $(shell cat VERSION)
MODULE := src/cs420x-a1534

PREFIX ?= /usr
DESTDIR ?=
MAKEPKG_FLAGS ?=
# The newest kernel tag upstream.lock records for every kernel series it knows
# (fetch-upstream.sh --all): the build never depends on which headers the
# building machine happens to have, and one package carries every series.
FETCH_ARGS ?= --all

SRCDIR = $(DESTDIR)$(PREFIX)/src/$(MODNAME)-$(VERSION)

.PHONY: install dist srcinfo arch-pkg arch-pkg-dev

install:
	install -dm755 "$(SRCDIR)"
	cp -a "$(MODULE)/." "$(SRCDIR)/"

	# Neither build artifacts nor VCS bookkeeping belong in the package.
	rm -f "$(SRCDIR)/.gitignore"

	# Build artifacts must never reach the package.
	find "$(SRCDIR)" -name '*.o' -delete
	find "$(SRCDIR)" -name '*.ko' -delete
	find "$(SRCDIR)" -name '*.mod*' -delete
	find "$(SRCDIR)" -name '.*.cmd' -delete
	rm -f "$(SRCDIR)/Module.symvers" "$(SRCDIR)/modules.order"

	# dkms.conf carries the version from the package, not a hardcoded string.
	sed -i "s/@PKGVER@/$(VERSION)/" "$(SRCDIR)/dkms.conf"
	# ... and the kernel series DKMS builds for, from kheaders/KERNEL-SERIES
	# through the script the pacman hook and the verifier ask, so the three
	# cannot name different series.
	re=$$(bash "$(MODULE)/contrib/pacman/kernel-series" --dkms-regex \
		--series-file "$(SRCDIR)/kheaders/KERNEL-SERIES") && \
	sed -i "s|@KERNEL_SERIES_RE@|$$(printf '%s' "$$re" | sed 's/[\\&|]/\\&/g')|" \
		"$(SRCDIR)/dkms.conf" && \
	grep -q '^BUILD_EXCLUSIVE_KERNEL="^(' "$(SRCDIR)/dkms.conf"

	install -Dm755 tools/macbook91-audio-verify \
		"$(DESTDIR)$(PREFIX)/bin/macbook91-audio-verify"
	sed -i "s/^VERSION='@PKGVER@'/VERSION='$(VERSION)'/" \
		"$(DESTDIR)$(PREFIX)/bin/macbook91-audio-verify"

	# Card policy for this machine. NOT optional, for two independent reasons:
	# the internal speaker path has no hardware volume control, so without the
	# software mixer the desktop slider does nothing and output is always full
	# scale; and the stock ACP profile set drops this card's only analog output
	# port whenever the headphone jack is plugged, leaving no sink at all. See
	# the files' own comments.
	install -Dm644 "$(SRCDIR)/contrib/wireplumber/51-macbook91-cs4208.conf" \
		"$(DESTDIR)$(PREFIX)/share/wireplumber/wireplumber.conf.d/51-macbook91-cs4208.conf"

	# The ACP profile set the drop-in selects, and the output path it names.
	# They live under this package's own prefix rather than in the
	# alsa-card-profiles directories, so nothing here can collide with another
	# package's files; ACP accepts both as absolute paths.
	install -Dm644 "$(SRCDIR)/contrib/acp/macbook91-cs4208.conf" \
		"$(DESTDIR)$(PREFIX)/share/macbook91-cs4208/acp/macbook91-cs4208.conf"
	install -Dm644 "$(SRCDIR)/contrib/acp/macbook91-output-speaker.conf" \
		"$(DESTDIR)$(PREFIX)/share/macbook91-cs4208/acp/macbook91-output-speaker.conf"

	# One list of supported kernel series for everything that must know it:
	# the pacman hook, which warns after a transaction about every installed
	# kernel of another series, and macbook91-audio-verify.
	install -Dm755 "$(SRCDIR)/contrib/pacman/kernel-series" \
		"$(DESTDIR)$(PREFIX)/lib/$(MODNAME)/kernel-series"
	sed -i "s/@PKGVER@/$(VERSION)/" "$(DESTDIR)$(PREFIX)/lib/$(MODNAME)/kernel-series"
	install -Dm644 "$(SRCDIR)/contrib/pacman/macbook91-cs4208-series.hook" \
		"$(DESTDIR)$(PREFIX)/share/libalpm/hooks/71-macbook91-cs4208-series.hook"

	install -Dm644 "$(SRCDIR)/README.md" \
		"$(DESTDIR)$(PREFIX)/share/doc/$(NAME)/README.md"

	find "$(DESTDIR)$(PREFIX)/src" -type f -exec chmod 644 {} +
	find "$(DESTDIR)$(PREFIX)/src" -type d -exec chmod 755 {} +
	chmod 644 "$(DESTDIR)$(PREFIX)/share/doc/$(NAME)/README.md"

dist:
	packaging/fetch-upstream.sh $(FETCH_ARGS)
	python3 packaging/mkdist.py

srcinfo:
	cd packaging/arch && makepkg --printsrcinfo > .SRCINFO

# The release build. The tarball holds no PKGBUILD, so pinning its checksum
# there does not change the tarball.
arch-pkg: dist
	@want=$$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" packaging/arch/PKGBUILD); \
	have=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256); \
	if [ "$$want" != "$$have" ]; then \
		echo "arch-pkg: error: the PKGBUILD pins sha256sums $$want, but the tarball is $$have" >&2; \
		echo "  Set sha256sums to $$have, run make srcinfo, commit with --amend, then run make arch-pkg again" >&2; \
		exit 1; \
	fi
	$(MAKE) --no-print-directory _arch-build

arch-pkg-dev:
	packaging/fetch-upstream.sh $(FETCH_ARGS)
	python3 packaging/mkdist.py --allow-dirty
	$(MAKE) --no-print-directory _arch-build PIN=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256)

# makepkg extracts into $$srcdir without clearing it, so a file deleted from
# the tree would survive into the next package (observed once); build/arch
# is recreated every time and makepkg runs with --cleanbuild.
_arch-build:
	rm -rf build/arch
	mkdir -p build/arch
	cp packaging/arch/PKGBUILD packaging/arch/$(MODNAME).install dist/$(NAME)-$(VERSION).tar build/arch/
	if [ -n "$(PIN)" ]; then \
		sed -i "s/^sha256sums=('[0-9a-f]*')/sha256sums=('$(PIN)')/" build/arch/PKGBUILD; \
	fi
	cd build/arch && makepkg --cleanbuild --force --noconfirm $(MAKEPKG_FLAGS)
	cp build/arch/$(NAME)-$(VERSION)-*.pkg.tar.zst dist/
