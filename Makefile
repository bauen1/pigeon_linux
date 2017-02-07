#!/usr/bin/make -f

# BIG LIST OF TODO AND FIXME
# 1. somewhat similar naming convention (src/kernel vs build/linux)
# 2. copying of glibc sysroot is somewhat broken

################################################################################
# Variables                                                                    #
################################################################################

SRC ?=$(PWD)/src
BUILD ?=$(PWD)/build
DOCS ?=$(PWD)/docs
NUM_JOBS ?=4

# Optimize for size, strip, disable stack smash protection (FIXME), protect
# against bad implementations
CFLAGS ?=-Os -s -fno-stack-protector -U_FORTIFY_SOURCE

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
qemu: $(BUILD)/initrd.img $(BUILD)/bzImage
	# FIXME: there seems to be a bug that on the first run with a newly build
	# initrd the kernel crashes due to acpi (for what ever reason)
	sleep 3
	-sync
	qemu-system-x86_64 -initrd $(BUILD)/initrd.img -kernel $(BUILD)/bzImage

qemu_serial: $(BUILD)/initrd.img $(BUILD)/bzImage
	sleep 3
	-sync
	qemu-system-x86_64 -initrd $(BUILD)/initrd.img -kernel $(BUILD)/bzImage -nographic -append console=ttyS0
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

# busybox

BUSYBOX_DOWNLOAD_FILE=busybox-1.22.0.tar.bz2
BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/$(BUSYBOX_DOWNLOAD_FILE)

$(SRC)/$(BUSYBOX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BUSYBOX_DOWNLOAD_URL) -O $@

$(SRC)/busybox: $(SRC)/$(BUSYBOX_DOWNLOAD_FILE)
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

################################################################################
# Linux kernel                                                                 #
################################################################################

LINUX_KERNEL_MAKE=$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux -j $(NUM_JOBS)

# Generate the default config for the kernel
$(BUILD)/linux/.config: $(SRC)/kernel
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE) defconfig

# generate the kernel in the vmlinux format
$(BUILD)/linux/vmlinux: $(BUILD)/linux/.config
	$(LINUX_KERNEL_MAKE) vmlinux

# generate the kernel in the compressed self-extracting bzImage format
$(BUILD)/linux/arch/x86/boot/bzImage: $(BUILD)/linux/vmlinux
	$(LINUX_KERNEL_MAKE) bzImage

# copy it (FIXME: move this)
$(BUILD)/bzImage: $(BUILD)/linux/arch/x86/boot/bzImage
	cp $< $@

# install the kernel headers
$(BUILD)/install/linux/include: $(BUILD)/linux/vmlinux
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE)  INSTALL_HDR_PATH=$(@D) headers_install
	touch $@

# install the kernel modules and firmware
$(BUILD)/install/linux/lib: $(BUILD)/linux/vmlinux
	mkdir -p $@ && rm -rf $@/* && mkdir -p $@/modules $@/firmware
	$(LINUX_KERNEL_MAKE) modules
	$(LINUX_KERNEL_MAKE) INSTALL_MOD_PATH=$(BUILD)/install/linux modules_install
	$(LINUX_KERNEL_MAKE) INSTALL_FW_PATH=$(BUILD)/install/linux/lib/firmware firmware_install
	touch $@

#
$(BUILD)/install/linux: $(BUILD)/install/linux/include $(BUILD)/install/linux/lib
	touch $@

################################################################################
# glibc                                                                        #
################################################################################

GLIBC_CFLAGS="$(CFLAGS)"

# configure glibc for compile
$(BUILD)/glibc/Makefile: $(SRC)/glibc $(BUILD)/install/linux
	mkdir -p $(@D) && rm -rf $(@D)/*
	cd "$(@D)" ; $(SRC)/glibc/configure \
		--prefix= \
		--with-headers="$(BUILD)/install/linux/include" \
		--with-kernel=4.0.0 \
		--without-gd \
		--without-selinux \
		--disable-werror \
		CFLAGS=$(GLIBC_CFLAGS) && touch $@
		# FIXME: what does the line above do ?

# build glibc
$(BUILD)/glibc: $(BUILD)/glibc/Makefile
	$(MAKE) -C $(BUILD)/glibc -j $(NUM_JOBS) && touch $@

# install glibc
$(BUILD)/install/glibc: $(BUILD)/glibc
	$(MAKE) -C $(BUILD)/glibc DESTDIR=$@ install -j $(NUM_JOBS) && touch $@

################################################################################
# sysroot                                                                      #
################################################################################

# create a sysroot (headers and libraries)
$(BUILD)/prepared/sysroot: $(BUILD)/install/linux $(BUILD)/install/glibc
	mkdir -p $@ && rm -rf $@/*
	cp -dR --preserve=all $(BUILD)/install/linux/* $@/
	cp -dR --preserve=all $(BUILD)/install/glibc/* $@/
	mkdir -p $@/usr
	# TODO: not sure if the commands below are needed
	cd $@/usr &&
		ln -s ../include include &&
		ln -s ../lib lib
	touch $@

################################################################################
# busybox                                                                      #
################################################################################

# Escape / and \ because sed uses them for magic
SYSROOT_ESCAPED=$(subst /,\/,$(subst \,\\,$(BUILD)/prepared/sysroot))

# TODO: remove as many flags and recompile busybox to see which are actually needed

BUSYBOX_MAKE=$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox -j $(NUM_JOBS) CFLAGS="$(CFLAGS) -fomit-frame-pointer"

$(BUILD)/busybox/.config: $(SRC)/busybox $(BUILD)/prepared/sysroot
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(BUSYBOX_MAKE) defconfig
	## For macOS, add '.bak' behind -i
	## ( btw my congratulations if you compile this under macOS or BSD
	## or something else than linux )
	cd $(@D) ; sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/g' .config
	# dynamic linking rules!
	##
	cd $(@D) ; sed -i 's/.*CONFIG_SYSROOT.*/CONFIG_SYSROOT="$(SYSROOT_ESCAPED)"/g' .config

$(BUILD)/busybox/busybox: $(BUILD)/busybox/.config $(BUILD)/prepared/sysroot
	$(BUSYBOX_MAKE) all && touch $@

################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/initrd
	$(shell cd $< && find . | cpio -o -H newc | gzip > $@ )

$(BUILD)/initrd: $(BUILD)/busybox/busybox $(SRC)/initfs $(SRC)/initfs/init
	# TODO: the copying isn't really working
	mkdir -p $@ && rm -rf $@/*
	# create the important directories
	cd $@ && mkdir -p bin dev lib lib64 mnt proc root sbin sys tmp usr usr/bin usr/sbin
	# cp -dR --preserve=all
	cp -dR --preserve=all$(SRC)/initfs/* $@/
	# create needed directories if not already present
	cd $@ && mkdir -p bin boot dev lib lib64 mnt proc root sbin sys tmp usr
	# copy busybox in
	cp -dR --preserve=all $(BUILD)/busybox/busybox $@/bin/busybox
	# copy the sysroot over (kernel headers and glibc libraries)
	cp -dR --preserve=all $(BUILD)/prepared/sysroot/* $@/
	# we need the linkers to be where they should be
	cp --preserve=all $@/lib/ld-linux* $@/lib64
	#
	touch $@

################################################################################
#                                                                              #
################################################################################
