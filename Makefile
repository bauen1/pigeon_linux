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

.DEFAULT: help
.PHONY: info
info:
	@echo "targets:         "
	@echo "	                "
	@echo "	all             "
	@echo "	                "
	@echo "	clean           "
	@echo "	clean_src       "
	@echo "	                "
	@echo "	qemu            "
	@echo "	                "
	@echo "	qemu_serial     "
	@echo "	                "

.PHONY: all
all: qemu

.PHONY: clean
clean:
	rm -rf $(BUILD)/*
	rm -rf $(SRC)/kernel
	rm -rf $(SRC)/busybox

.PHONY: clean_src
clean_src:
	rm -rf $(SRC)/*.tar*

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
LINUX_KERNEL_DOWNLOAD_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/$(LINUX_KERNEL_DOWNLOAD_FILE)

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
	ln -s linux/arch/x86/boot/bzImage "$@"

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

SYSROOT=$(BUILD)/sysroot

# create a sysroot (headers and libraries)
$(SYSROOT): $(BUILD)/install/linux $(BUILD)/install/glibc
	mkdir -p $@ && rm -rf $@/*
	rsync -a $(BUILD)/install/linux/ $@/
	rsync -a $(BUILD)/install/glibc/ $@/
	touch $@

################################################################################
# busybox                                                                      #
################################################################################

# Escape / and \ because sed uses them for magic
SYSROOT_ESCAPED=$(subst /,\/,$(subst \,\\,$(SYSROOT)))

# TODO: remove as many flags and recompile busybox to see which are actually needed

BUSYBOX_MAKE=$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox -j $(NUM_JOBS) CFLAGS="$(CFLAGS) -fomit-frame-pointer"

$(BUILD)/busybox/.config: $(SRC)/busybox $(SYSROOT)
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

$(BUILD)/busybox/busybox: $(BUILD)/busybox/.config $(SYSROOT)
	$(BUSYBOX_MAKE) all && touch $@

################################################################################
# rootfs                                                                       #
################################################################################

$(BUILD)/rootfs: $(SRC)/initfs $(BUILD)/busybox/busybox $(SYSROOT)
	rm -rf $@ && mkdir -p $@
	# create the basic filesystem layout
	# please keep these sorted
	install -d -m 0755 $@/bin
	install -d -m 0755 $@/boot
	install -d -m 0755 $@/dev
	install -d -m 0755 $@/dev/pts
	install -d -m 0755 $@/dev/shm
	install -d -m 0755 $@/etc
	install -m 0644 $(SRC)/filesystem/etc/fstab $@/etc/fstab
	install -m 0644 $(SRC)/filesystem/etc/group $@/etc/group
	install -m 0600 $(SRC)/filesystem/etc/gshadow $@/etc/gshadow
	install -m 0644 $(SRC)/filesystem/etc/issue $@/etc/issue
	install -m 0644 $(SRC)/filesystem/etc/motd $@/etc/motd
	ln -s ../proc/self/mounts $@/etc/mtab
	#install -m 0644 $(SRC)/filesystem/etc/os-version $@/etc/os-version
	install -m 0644 $(SRC)/filesystem/etc/passwd $@/etc/passwd
	install -m 0644 $(SRC)/filesystem/etc/securetty $@/etc/securetty
	install -m 0600 $(SRC)/filesystem/etc/shadow $@/etc/shadow
	install -m 0644 $(SRC)/filesystem/etc/shells $@/etc/shells
	install -d -m 0755 $@/home
	install -d -m 0755 $@/lib
	install -d -m 0755 $@/lib/modules
	install -d -m 0755 $@/lib32
	install -d -m 0755 $@/lib64
	install -d -m 0755 $@/mnt
	install -d -m 0755 $@/opt
	install -d -m 0755 $@/opt/bin
	install -d -m 0755 $@/opt/sbin
	install -d -m 0555 $@/proc
	install -d -m 0750 $@/root
	install -d -m 0755 $@/run
	install -d -m 0755 $@/sboot
	install -d -m 0555 $@/sys
	install -d -m 1777 $@/tmp
	install -d -m 0755 $@/usr
	install -d -m 0755 $@/usr/bin
	install -d -m 0755 $@/usr/include
	install -d -m 0755 $@/usr/lib
	install -d -m 0755 $@/usr/lib32
	install -d -m 0755 $@/usr/lib64
	install -d -m 0755 $@/usr/sbin
	install -d -m 0755 $@/usr/share
	install -d -m 0755 $@/usr/share/man
	install -d -m 0755 $@/usr/share/man/man{1,2,3,4,5,6,7,8}
	install -d -m 0755 $@/usr/src
	install -d -m 0755 $@/usr/var
	install -d -m 0755 $@/var
	install -d -m 0755 $@/var/cache
	install -d -m 0755 $@/var/empty
	install -d -m 0755 $@/var/ftp
	install -d -m 0755 $@/var/lib
	install -d -m 0755 $@/var/lib/pkg
	install -d -m 0755 $@/var/lock
	install -d -m 0755 $@/var/log
	install -d -m 0755 $@/var/log/old
	#install -d -m 0755 $@/var/mail
	ln -s spool/mail $@/var/mail
	install -d -m 0755 $@/var/run
	install -d -m 0755 $@/var/run/utmp
	install -d -m 0755 $@/var/spool
	install -d -m 1777 $@/var/spool/mail
	install -d -m 1777 $@/var/tmp
	# copy all the files in the sysroot over
	rsync -avr $(SYSROOT)/ $@/
	rsync -avr $(BUILD)/busybox/busybox $@/bin/busybox
	# update the date on the directory itself
	touch $@

################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/initrd
	# pack the initramfs and make everything be owned by root
	$(shell cd $< && find . | cpio -o -H newc -R 0:0 | gzip > $@ )

$(BUILD)/initrd: $(SRC)/initfs $(BUILD)/rootfs
	rm -rf $@ && mkdir -p $@
	rsync -avr $(BUILD)/rootfs/ $@/
	rsync -avrI $(SRC)/initfs $@/
	touch $@

################################################################################
#                                                                              #
################################################################################
