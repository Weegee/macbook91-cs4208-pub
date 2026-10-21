# SPDX-License-Identifier: GPL-2.0-or-later
# Out-of-tree build of the MacBook9,1 (A1534) CS4208 codec driver.
#
# The module is deliberately named snd-hda-codec-cs420x, i.e. the same as the
# in-tree module. DKMS installs it under /lib/modules/<kver>/updates/, which
# depmod prefers over kernel/, so it shadows the in-tree codec. Removing the
# DKMS module and running depmod restores the stock module with no other
# change - that is the whole rollback story.
#
# Nothing under kheaders/, upstream/ or <series>/cs420x.c is tracked in this
# project's repository. packaging/fetch-upstream.sh assembles all of it, one
# kernel tag per series recorded in packaging/upstream.lock, and the result is
# what ships in /usr/src. The private HDA headers have to be fetched at all because
# linux-cachyos-headers - and every other headers package - installs only
# Kconfig files under sound/hda/. See UPSTREAM.txt for what is fetched and
# packaging/upstream.lock for the hashes that gate it.
#
# Several kernel series are shipped side by side (kheaders/KERNEL-SERIES lists
# them). The series of the kernel being built for is read from its
# utsrelease.h, like macbook91-hw-fixes' applesmc does, and selects
# <series>/cs420x.c and kheaders/<series>/. A kernel of a series that is not
# shipped is refused cleanly and keeps its in-tree codec; dkms.conf keeps DKMS
# from trying at all.
#
# This Makefile never fetches anything. A DKMS rebuild during a kernel upgrade
# runs entirely offline, against the tree it was given.

MODNAME := snd-hda-codec-cs420x

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)
PKGVER ?= 0

# The kernel's series (UTS_RELEASE 7.2.11-1-x -> 7.2) and the series this tree
# ships. BSERIES, the series whose sources are built, is computed here and
# handed to the kernel's own make as a command-line variable: the Kbuild pass
# reads this file again from inside the kernel tree, where neither KDIR nor
# PWD mean what they mean here.
KSERIES := $(shell sed -n 's/.*UTS_RELEASE "\([0-9]*\.[0-9]*\).*/\1/p' \
                       $(KDIR)/include/generated/utsrelease.h 2>/dev/null)
SHIPPED := $(shell cat $(PWD)/kheaders/KERNEL-SERIES 2>/dev/null)
ifneq ($(filter $(KSERIES),$(SHIPPED)),)
  BSERIES := $(KSERIES)
else ifeq ($(A1534_ALLOW_SERIES_MISMATCH),1)
  BSERIES := $(lastword $(SHIPPED))
endif

obj-m += $(MODNAME).o
$(MODNAME)-y := $(BSERIES)/cs420x.o
ccflags-y += -I$(src) -I$(src)/kheaders/$(BSERIES)

# Reproducible source identity, so the verifier can prove which source
# produced the module that is actually loaded. modinfo alone describes the
# file on disk, which may differ from a module loaded before an update. It
# hashes the selected series' cs420x.c, so each series has its own.
SRCROOT := $(or $(src),$(PWD))
SRCIDFILES := a1534_pcm.h a1534_match.h a1534_snapshot.h a1534_i2c.h vendored/a1534_sequence.h
SRCID := $(shell cat $(SRCROOT)/$(BSERIES)/cs420x.c $(addprefix $(SRCROOT)/,$(SRCIDFILES)) 2>/dev/null \
                 | sha256sum | cut -c1-16)
ccflags-y += -DA1534_SRCID=\"$(PKGVER)+$(SRCID)\"

# Fail closed on a compiler-family mismatch. CONFIG_CC_IS_CLANG=y means the
# kernel's per-object flags are clang-only, so an out-of-tree GCC build does
# not merely warn - it dies on the first unknown flag (-mstack-alignment=8 and
# friends). Take the family from the target kernel's own .config; never
# hardcode a compiler version.
KCONFIG := $(KDIR)/.config
ifeq ($(shell grep -qx 'CONFIG_CC_IS_CLANG=y' $(KCONFIG) 2>/dev/null && echo clang),clang)
  LLVM ?= 1
  export LLVM
endif

all: check
	$(MAKE) -C $(KDIR) M=$(PWD) BSERIES=$(BSERIES) modules

# Refuse to build against anything but a complete, matching kernel tree, and
# against anything but a complete, self-consistent source tree.
check:
	@test -r "$(PWD)/kheaders/KERNEL-SERIES" -a -r "$(PWD)/UPSTREAM.sha256" || \
	  { echo "ERROR: the upstream-derived sources are not assembled."; \
	    echo "       This tree is a checkout, not a package: <series>/cs420x.c, upstream/"; \
	    echo "       and kheaders/ are generated and not tracked. Run"; \
	    echo "           packaging/fetch-upstream.sh"; \
	    echo "       once, then build again. A tree installed from the package is"; \
	    echo "       already complete and never needs this."; exit 1; }
	@test -r "$(KCONFIG)" || { echo "ERROR: no .config at $(KCONFIG)"; exit 1; }
	@test -r "$(KDIR)/Module.symvers" || { echo "ERROR: no Module.symvers in $(KDIR)"; exit 1; }
	@test -r "$(KDIR)/include/generated/utsrelease.h" || { echo "ERROR: no utsrelease.h in $(KDIR)"; exit 1; }
# The series gate. sound/hda/common/*.h are internal headers with no ABI
# promise, so a module built against another series' copy could silently read
# and write wrong struct offsets. Each shipped series carries its own copy, and
# a kernel of any other series is refused here instead of being built against
# the wrong one. That is not a failure of the tree: the kernel keeps its
# in-tree codec, and dkms.conf's BUILD_EXCLUSIVE_KERNEL keeps DKMS from
# calling this at all for such a kernel.
	@kernel='$(KSERIES)'; shipped='$(SHIPPED)'; \
	 case " $$shipped " in \
	 *" $$kernel "*) ;; \
	 *) echo "ERROR: Linux $$kernel is not a kernel series this tree ships ($$shipped)."; \
	    echo "       No module is built and the kernel keeps its in-tree codec."; \
	    echo "       To add the series, in the repository: record a tag of it with"; \
	    echo "       packaging/fetch-upstream.sh --tag vX.Y.Z --accept-new, commit"; \
	    echo "       packaging/upstream.lock, then make arch-pkg-dev."; \
	    echo "       Or set A1534_ALLOW_SERIES_MISMATCH=1 to build the newest shipped series"; \
	    echo "       against this kernel if you have checked the headers yourself."; \
	    [ "$(A1534_ALLOW_SERIES_MISMATCH)" = "1" ] || exit 1 ;; \
	 esac
	@test -n "$(BSERIES)" -a -r "$(PWD)/$(BSERIES)/cs420x.c" \
	  -a -r "$(PWD)/upstream/$(BSERIES)/cs420x.c" -a -r "$(PWD)/kheaders/$(BSERIES)/hda_local.h" || \
	  { echo "ERROR: the sources for Linux series '$(BSERIES)' are missing from this tree."; exit 1; }
# The derived <series>/cs420x.c is not listed in UPSTREAM.sha256: for it the
# SRCID (make srcid) is the only integrity record, and it changes with any edit.
# These two say the packaged copy is intact, and nothing more. Provenance
# - that the bytes are the kernel's - is established once, at package
# build time, by packaging/fetch-upstream.sh against packaging/upstream.lock;
# a manifest generated beside the files it describes cannot prove where
# they came from. What it can catch is a truncated tarball, a half-written
# /usr/src, or an edit made in place after installation, and that is worth
# catching before a module is built and loaded into a running kernel.
	@cd $(PWD) && sha256sum -c UPSTREAM.sha256 >/dev/null || \
	  { echo "ERROR: the assembled upstream sources do not match UPSTREAM.sha256"; exit 1; }
	@cd $(PWD)/vendored && sha256sum -c PROVENANCE.sha256 >/dev/null || \
	  { echo "ERROR: the A1534 sequence does not match PROVENANCE.sha256"; exit 1; }
	@if grep -qx 'CONFIG_CC_IS_CLANG=y' $(KCONFIG); then \
	   command -v clang >/dev/null || { echo "ERROR: kernel is CONFIG_CC_IS_CLANG=y but clang is not installed; install it with: sudo pacman -S clang lld llvm"; exit 1; }; \
	 elif grep -qx 'CONFIG_CC_IS_GCC=y' $(KCONFIG); then \
	   command -v gcc >/dev/null || { echo "ERROR: kernel is CONFIG_CC_IS_GCC=y but gcc is not installed; install it with: sudo pacman -S gcc"; exit 1; }; \
	 else \
	   echo "ERROR: kernel .config declares neither CONFIG_CC_IS_CLANG nor CONFIG_CC_IS_GCC"; exit 1; \
	 fi

# The source identity the module of series BSERIES would carry, without the
# package version: make srcid BSERIES=7.2
srcid:
	@echo $(SRCID)

clean:
	@for s in $(SHIPPED); do \
	  $(MAKE) -C $(KDIR) M=$(PWD) BSERIES=$$s clean || exit 1; \
	done

.PHONY: all clean check srcid
