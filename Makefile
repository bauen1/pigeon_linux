#!/usr/bin/make -f

################################################################################
# Variables                                                                    #
################################################################################

SRC ?=$(PWD)/src
BUILD ?=$(PWD)/build
DOCS ?=$(PWD)/docs

################################################################################
# Special Targets                                                              #
################################################################################

.DEFAULT .PHONY: all
all: linux_src
	# TODO: Implement

.PHONY: clean
clean:
	# TODO: Implement

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
linux_kernel: $(SRC)/kernel
	##

################################################################################
#                                                                              #
################################################################################
