#!/usr/bin/make -f

# BIG LIST OF TODO AND FIXME
# 1. somewhat similar naming convention (src/kernel vs build/linux)
#
#
#
#
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
	tar -xvf $< -C$@

# busybox

BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/busybox-1.26.2.tar.bz2
BUSYBOX_DOWNLOAD_FILE=busybox-1.26.2.tar.bz2

.PHONY: busybox_src
busybox_src: $(SRC)/busybox

$(SRC)/$(BUSYBOX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BUSYBOX_DOWNLOAD_URL) -O $@

$(SRC)/busybox: $(SRC)/$(BUSYBOX_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C$@

# TODO: glibc (atm we are just "stealing" the one from the host)

################################################################################
# Linux kernel                                                                 #
################################################################################

.PHONY: linux_kernel
linux_kernel: $(BUILD)/linux/arch/x86/boot/bzImage
	@echo "Finished building the kernel"

$(BUILD)/linux/.config: linux_src
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux defconfig -j$(NUM_JOBS)

$(BUILD)/linux/vmlinux: $(BUILD)/linux/.config
	$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux vmlinux -j$(NUM_JOBS)

$(BUILD)/linux/arch/x86/boot/bzImage: $(BUILD)/linux/vmlinux
	$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux bzImage -j$(NUM_JOBS)

$(BUILD)/bzImage: $(BUILD)/linux/arch/x86/boot/bzImage
	cp $< $@

################################################################################
# busybox                                                                      #
################################################################################

busybox: busybox_src

$(BUILD)/busybox/.config: busybox_src
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox defconfig -j$(NUM_JOBS)

$(BUILD)/busybox/busybox: $(BUILD)/busybox/.config
	$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox all -j$(NUM_JOBS)

################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/busybox/busybox
	# TODO

################################################################################
#                                                                              #
################################################################################
