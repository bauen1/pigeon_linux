#!/usr/bin/make -f

# BIG LIST OF TODO AND FIXME
# 1. somewhat similar naming convention (src/kernel vs build/linux)
#

################################################################################
# Variables                                                                    #
################################################################################

SRC ?=$(PWD)/src
BUILD ?=$(PWD)/build
DOCS ?=$(PWD)/docs
NUM_JOBS ?=4

################################################################################
# Special Targets                                                              #
################################################################################

.DEFAULT .PHONY: all
all: qemu
	# TODO: Implement

.PHONY: clean
clean:
	# TODO: Implement
	rm -rf $(BUILD)/*
	rm -rf $(SRC)/kernel
	rm -rf $(SRC)/busybox

.POHNY: qemu
qemu: $(BUILD)/initrd.img $(BUILD)/bzImage
	qemu-system-i386 -initrd $(BUILD)/initrd.img -kernel $(BUILD)/bzImage

################################################################################
# Source downloading                                                           #
################################################################################

# TODO: Macros / Functions to make somewhat more readable code

# linux kernel

LINUX_KERNEL_DOWNLOAD_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.9.8.tar.xz
LINUX_KERNEL_DOWNLOAD_FILE=linux-4.9.8.tar.xz

.PHONY: linux_src
linux_src: $(SRC)/kernel

$(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE):
	rm -rf $@ && wget $(LINUX_KERNEL_DOWNLOAD_URL) -O $@

$(SRC)/kernel: $(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# busybox

BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/busybox-1.26.2.tar.bz2
BUSYBOX_DOWNLOAD_FILE=busybox-1.26.2.tar.bz2

.PHONY: busybox_src
busybox_src: $(SRC)/busybox

$(SRC)/$(BUSYBOX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BUSYBOX_DOWNLOAD_URL) -O $@

$(SRC)/busybox: $(SRC)/$(BUSYBOX_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# glibc

GLIBC_DOWNLOAD_URL=https://ftp.gnu.org/gnu/libc/glibc-2.24.tar.xz
GLIBC_DOWNLOAD_FILE=glibc-2.24.tar.xz

.PHONY: glibc_src
glibc_src: $(SRC)/glibc

$(SRC)/$(GLIBC_DOWNLOAD_FILE):
	rm -rf $@ && wget $(GLIBC_DOWNLOAD_URL) -O $@

$(SRC)/glibc: $(SRC)/$(GLIBC_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

################################################################################
# Linux kernel                                                                 #
################################################################################

.PHONY: linux_kernel
linux_kernel: $(BUILD)/linux/arch/x86/boot/bzImage
	@echo "Finished building the kernel"

$(BUILD)/linux/.config: linux_src
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux defconfig -j $(NUM_JOBS)

$(BUILD)/linux/vmlinux: $(BUILD)/linux/.config
	$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux vmlinux -j $(NUM_JOBS)

$(BUILD)/linux/arch/x86/boot/bzImage: $(BUILD)/linux/vmlinux
	$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux bzImage -j $(NUM_JOBS)

$(BUILD)/bzImage: $(BUILD)/linux/arch/x86/boot/bzImage
	cp $< $@

$(BUILD)/install/linux/include: $(BUILD)/linux/vmlinux
	mkdir -p $(@D) && rm -rf $(@D)/*
	make INSTALL_HDR_PATH=$(@D) headers_install -j $(NUM_JOBS)

################################################################################
# busybox                                                                      #
################################################################################

$(BUILD)/busybox/.config: busybox_src
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox defconfig -j $(NUM_JOBS)

$(BUILD)/busybox/busybox: $(BUILD)/busybox/.config
	$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox all -j $(NUM_JOBS)

################################################################################
# glibc                                                                        #
################################################################################


################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/initrd
	$(shell cd $< && find . | cpio -o -H newc | gzip > $@ )

$(BUILD)/initrd: $(BUILD)/busybox/busybox
	mkdir -p $@/{bin,boot,dev,etc,lib,lib64,mnt,root,sbin,tmp,usr}
	cp $(BUILD)/busybox/busybox $@/bin/busybox
	# "borrow" some libraries for the time being ( 'ldd build/busybox/busybox' )
	cp /lib/x86_64-linux-gnu/libm.so.6 $@/lib/x86_64-linux-gnu/libm.so.6
	cp /lib/x86_64-linux-gnu/libc.so.6 $@/lib/x86_64-linux-gnu/libc.so.6
	cp /lib64/ld-linux-x86-64.so.2 $@/lib64/ld-linux-x86-64.so.2

################################################################################
#                                                                              #
################################################################################
