#!/usr/bin/make -f

# BIG LIST OF TODO AND FIXME
# TODO: similar naming convention (src/kernel vs build/linux)

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
# ports                                                                        #
################################################################################

# TODO: make this abstract again
# Please note that dependencys must be resolved manually

BUILD_PORTS=$(BUILD)/ports
SRC_PORTS=$(SRC)/ports
STANDARD_PORT_BUILD=rm -rf $@ && mkdir -p $(@D) && rsync -a $</ $(@D)/ \
	&& cd $(@D) && export PACMAN="pacman --root $@" && makepkg

$(BUILD_PORTS)/filesystem/filesystem-1.0.pkg.tar.xz: $(SRC_PORTS)/filesystem
	$(STANDARD_PORT_BUILD)

$(BUILD_PORTS)/linux/linux-4.8.9.pkg.tar.xz: $(SRC_PORTS)/linux
	$(STANDARD_PORT_BUILD)

$(BUILD_PORTS)/glibc/glibc-2.25.pkg.tar.xz: $(SRC_PORTS)/glibc
	$(STANDARD_PORT_BUILD)

$(BUILD_PORTS)/busybox/busybox-1.26.2.pkg.tar.xz: $(SRC_PORTS)/busybox
	$(STANDARD_PORT_BUILD)

################################################################################
# rootfs                                                                       #
################################################################################

define install_port
	fakeroot /bin/sh -c 'pacman --rot "$@" -U $(BUILD_PORTS)/$(1)/$(1)-$(2).pkg.tar.xz'
endef

$(BUILD)/rootfs: $(SRC)/rootfs \
		$(BUILD_PORTS)/filesystem/filesystem-1.0.pkg.tar.xz \
		$(BUILD_PORTS)/linux/linux-4.8.9.pkg.tar.xz \
		$(BUILD_PORTS)/
	rm -rf $@ && mkdir -p $@
	# setup some temporary stuff for pacman
	fakeroot /bin/sh -c 'mkdir -m 0755 -p $@/var/{cache/pacman/pkg,lib/pacman,log}'
	#fakeroot /bin/sh -c 'pacman --root "$@" -U $(BUILD)/ports/filesystem-1.0.pkg.tar.xz'
	#fakeroot /bin
	$(call install_port,filesystem,1.0)
	$(call install_port,linux,4.8.9)
	$(call install_port,glibc,2.25)
	$(call install_port,busybox,1.26.2)
	rsync -a $(SRC)/rootfs/ $@/
	touch $@

################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/initrd
	# pack the initramfs and make everything be owned by root
	$(shell cd $< && find . | cpio -o -H newc -R 0:0 | gzip > $@ )

$(BUILD)/initrd: $(BUILD)/rootfs $(SRC)/initfs/init
	rm -rf $@ && mkdir -p $@
	rsync -a $(BUILD)/rootfs/ $@/
	cp --preserve=all $(SRC)/initfs/init $@/
	touch $@

################################################################################
#                                                                              #
################################################################################
