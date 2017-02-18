#!/usr/bin/make -f

# BIG LIST OF TODO AND FIXME
# TODO: similar naming convention (src/kernel vs build/linux)
# FIXME: copying of glibc sysroot is broken
# FIXME: dynamically link busybox and actually make it work

################################################################################
# Variables                                                                    #
################################################################################

SRC ?=$(PWD)/src
BUILD ?=$(PWD)/build
DOCS ?=$(PWD)/docs
NUM_JOBS ?=4

# Optimize for size, strip, protect against bad implementations
CFLAGS ?=-Os -s -U_FORTIFY_SOURCE

################################################################################
# Special Targets                                                              #
################################################################################

.DEFAULT .PHONY: all
all: qemu

.PHONY: clean
clean:
	rm -rf $(BUILD)/*
	rm -rf $(SRC)/kernel
	rm -rf $(SRC)/busybox

.POHNY: qemu
qemu: $(BUILD)/initrd.img $(BUILD)/kernel
	# FIXME: there seems to be a bug that on the first run with a newly build
	# initrd the kernel crashes due to acpi (for what ever reason, i'm running
	# qemu inside a virtualbox vm running debian 8 so that might be why )
	sleep 1
	-sync
	qemu-system-x86_64 -initrd $(BUILD)/initrd.img -kernel $(BUILD)/kernel -append vga=ask

qemu_serial: $(BUILD)/initrd.img $(BUILD)/kernel
	sleep 1
	-sync
	qemu-system-x86_64 -initrd $(BUILD)/initrd.img -kernel $(BUILD)/kernel -nographic -append console=ttyS0

################################################################################
# Source downloading                                                           #
################################################################################

# TODO: Macros / Functions to make somewhat more readable code

# linux kernel

LINUX_KERNEL_DOWNLOAD_FILE=linux-4.4.47.tar.xz
LINUX_KERNEL_DOWNLOAD_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.4.47.tar.xz

$(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE):
	rm -rf $@ && wget $(LINUX_KERNEL_DOWNLOAD_URL) -O $@

$(SRC)/kernel: $(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# glibc

GLIBC_DOWNLOAD_FILE=glibc-2.19.tar.xz
GLIBC_DOWNLOAD_URL=https://ftp.gnu.org/gnu/libc/$(GLIBC_DOWNLOAD_FILE)

$(SRC)/$(GLIBC_DOWNLOAD_FILE):
	rm -rf $@ && wget $(GLIBC_DOWNLOAD_URL) -O $@

$(SRC)/glibc: $(SRC)/$(GLIBC_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# busybox

BUSYBOX_DOWNLOAD_FILE=busybox-1.22.0.tar.bz2
BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/$(BUSYBOX_DOWNLOAD_FILE)

$(SRC)/$(BUSYBOX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BUSYBOX_DOWNLOAD_URL) -O $@

$(SRC)/busybox: $(SRC)/$(BUSYBOX_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# bash

BASH_DOWNLOAD_FILE=bash-4.4.tar.gz
BASH_DOWNLOAD_URL=http://ftpmirror.gnu.org/bash/$(BASH_DOWNLOAD_FILE)

$(SRC)/$(BASH_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BASH_DOWNLOAD_URL) -O $@

$(SRC)/bash: $(SRC)/$(BASH_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# dpkg

DPKG_DOWNLOAD_FILE=dpkg_1.18.22.tar.xz
DPKG_DOWNLOAD_URL=http://ftp.debian.org/debian/pool/main/d/dpkg/$(DPKG_DOWNLOAD_FILE)

$(SRC)/$(DPKG_DOWNLOAD_FILE):
	rm -rf $@ && wget $(DPKG_DOWNLOAD_URL) -O $@

$(SRC)/dpkg: $(SRC)/$(DPKG_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

################################################################################
# Linux kernel                                                                 #
################################################################################

LINUX_KERNEL_MAKE=$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux -j $(NUM_JOBS)

# Generate the default config for the kernel
$(BUILD)/linux/.config: $(SRC)/kernel
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE) defconfig
	# Enable VESA framebuffer support
	cd $(@D) && sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" .config
	touch $@

# generate the kernel in the compressed self-extracting bzImage format
$(BUILD)/linux/arch/x86/boot/bzImage: $(BUILD)/linux/.config #$(BUILD)/linux/vmlinux
	$(LINUX_KERNEL_MAKE) bzImage

$(BUILD)/kernel: $(BUILD)/linux/arch/x86/boot/bzImage
	cp $< $@

###

# install the kernel headers
$(BUILD)/install/linux/include: $(BUILD)/linux/.config
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE)  INSTALL_HDR_PATH=$(@D) headers_install
	touch $@

# install the kernel modules and firmware
$(BUILD)/install/linux/lib: $(BUILD)/linux/.config
	mkdir -p $@ && rm -rf $@/* && mkdir -p $@/modules $@/firmware
	$(LINUX_KERNEL_MAKE) modules
	$(LINUX_KERNEL_MAKE) INSTALL_MOD_PATH=$(BUILD)/install/linux modules_install
	#$(LINUX_KERNEL_MAKE) INSTALL_FW_PATH=$(BUILD)/install/linux/lib/firmware firmware_install
	touch $@

#
$(BUILD)/install/linux: $(BUILD)/install/linux/include $(BUILD)/install/linux/lib
	touch $@

################################################################################
# glibc                                                                        #
################################################################################

# configure glibc for compile
$(BUILD)/glibc/Makefile: $(SRC)/glibc $(BUILD)/install/linux
	mkdir -p $(@D) && rm -rf $(@D)/*
	cd "$(@D)" ; $(SRC)/glibc/configure \
		--prefix= \
		--with-headers="$(BUILD)/install/linux/include" \
		--with-kernel=3.2.0 \
		--without-gd \
		--without-selinux \
		--disable-werror \
		--enable-add-ons \
		--enable-stack-protector \
		CFLAGS="$(CFLAGS)" && touch $@

# build glibc
$(BUILD)/glibc: $(BUILD)/glibc/Makefile
	$(MAKE) -C $(BUILD)/glibc -j $(NUM_JOBS) && touch $@

# install glibc
$(BUILD)/install/glibc: $(BUILD)/glibc
	$(MAKE) -C $(BUILD)/glibc DESTDIR=$@ install -j $(NUM_JOBS) && touch $@

################################################################################
# sysroot                                                                      #
################################################################################

SYSROOT=$(BUILD)/prepared/sysroot

# create a sysroot (headers and libraries)
$(SYSROOT): $(BUILD)/install/linux $(BUILD)/install/glibc
	mkdir -p $@ && rm -rf $@/*
	rsync -a $(BUILD)/install/linux/ $@/
	rsync -a $(BUILD)/install/glibc/ $@/
	mkdir -p $@/usr
	# TODO: not sure if the commands below are needed
	#cd $@/usr && \
	#	ln -s ../include include && \
	#	ln -s ../lib lib
	touch $@

################################################################################
# busybox                                                                      #
################################################################################

# Escape / and \ because sed uses them for magic
SYSROOT_ESCAPED=$(subst /,\/,$(subst \,\\,$(SYSROOT)))

# TODO: remove as many flags and recompile busybox to see which are actually needed

BUSYBOX_MAKE=$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox -j $(NUM_JOBS) CFLAGS="$(CFLAGS) -fomit-frame-pointer"

$(BUILD)/busybox/.config: $(SRC)/busybox $(BUILD)/prepared/sysroot
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(BUSYBOX_MAKE) defconfig
	## For macOS, add '.bak' behind -i
	## ( btw my congratulations if you compile this under macOS or BSD
	## or something else than linux )
	# enable static linking for the time being FIXME: get this to work
	cd $(@D) && sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/g' .config
	# dynamic linking rules!
	##
	cd $(@D) && sed -i 's/.*CONFIG_SYSROOT.*/CONFIG_SYSROOT="$(SYSROOT_ESCAPED)"/g' .config

$(BUILD)/busybox/busybox: $(BUILD)/busybox/.config $(BUILD)/prepared/sysroot
	$(BUSYBOX_MAKE) all && touch $@

################################################################################
# bash                                                                         #
################################################################################

$(BUILD)/bash/Makefile: $(SRC)/bash
	rm -rf $(@D) && mkdir -p $(@D)
	cd "$(@D)" ; $(SRC)/bash/configure \
		--with-sysroot=$(SYSROOT) \
		CFLAGS="$(CFLAGS)" && touch $@

$(BUILD)/bash: $(BUILD)/bash/Makefile
	$(MAKE) -C $(BUILD)/bash -j $(NUM_JOBS) && touch $@

$(BUILD)/install/bash: $(BUILD)/bash
	$(MAKE) -C $(BUILD)/bash -j $(NUM_JOBS) DESTDIR=$@ install && touch $@

################################################################################
# dpkg                                                                         #
################################################################################

$(BUILD)/dpkg/Makefile: $(SRC)/dpkg $(BUILD)/prepared/sysroot
	mkdir -p $(@D) && rm -rf $(@D)/*
	cd "$(@D)" ; $(SRC)/dpkg/configure \
		--prefix=/usr \
		--with-sysroot=$(SYSROOT) \
		--without-libmd \
		--without-libz \
		--without-libbz2 \
		--without-liblzma \
		--without-selinux \
		CFLAGS="$(CFLAGS)" && touch $@
		# Please note that dpkg might depend on features of gzip / bz2 / xz that
		# aren't included in busybox
		# TODO: build lib* for dpkg

$(BUILD)/dpkg: $(BUILD)/dpkg/Makefile
	$(MAKE) -C $(BUILD)/dpkg -j $(NUM_JOBS) && touch $@

$(BUILD)/install/dpkg: $(BUILD)/dpkg
	$(MAKE) -C $(BUILD)/dpkg -j $(NUM_JOBS) DESTDIR=$@ install && touch $@

################################################################################
# rootfs                                                                       #
################################################################################

################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/initrd
	# pack the initramfs and make everything be owned by root
	$(shell cd $< && find . | cpio -o -H newc -R 0:0 | gzip > $@ )

$(BUILD)/initrd: $(BUILD)/install/dpkg $(SRC)/initfs $(BUILD)/busybox/busybox $(BUILD)/install/bash \
		$(BUILD)/prepared/sysroot $(SRC)/initfs/init
	# TODO: the copying isn't really working
	mkdir -p $@ && rm -rf $@/*
	@# create needed directories if not already present
	cd $@ && mkdir -p bin boot dev etc lib lib64 mnt proc root sbin sys tmp usr usr/bin usr/sbin
	@# -a : copy everything (timestamps etc )
	@#
	rsync -a $(SYSROOT)/ $@/
	rsync -a $(BUILD)/install/dpkg $@/
	rsync -a $(BUILD)/busybox/busybox $@/bin/busybox
	rsync -a $(SRC)/initfs/ $@/
	# copy the loader
	cp --preserve=all $@/lib/ld* $@/lib64
	@#
	touch $@

################################################################################
#                                                                              #
################################################################################
