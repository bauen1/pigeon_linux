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
clean: build_clean
	# TODO: Implement
	rm -rf $(SRC)/kernel
	rm -rf $(SRC)/busybox

.PHONY: build_clean
build_clean:
	rm -rf $(BUILD)/*

.POHNY: qemu
qemu: $(BUILD)/initrd.img $(BUILD)/bzImage
	qemu-system-x86_64 -initrd $(BUILD)/initrd.img -kernel $(BUILD)/bzImage

################################################################################
# Source downloading                                                           #
################################################################################

# TODO: Macros / Functions to make somewhat more readable code

# linux kernel

LINUX_KERNEL_DOWNLOAD_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.9.8.tar.xz
LINUX_KERNEL_DOWNLOAD_FILE=linux-4.9.8.tar.xz

$(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE):
	rm -rf $@ && wget $(LINUX_KERNEL_DOWNLOAD_URL) -O $@

$(SRC)/kernel: $(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE)
	mkdir -p $@ && rm -rf $@/*
	tar -xvf $< -C $@ --strip-components=1

# busybox

BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/busybox-1.26.2.tar.bz2
BUSYBOX_DOWNLOAD_FILE=busybox-1.26.2.tar.bz2

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

LINUX_KERNEL_MAKE=$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux -j $(NUM_JOBS)

$(BUILD)/linux/.config: $(SRC)/kernel
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE) defconfig

$(BUILD)/linux/vmlinux: $(BUILD)/linux/.config
	$(LINUX_KERNEL_MAKE) vmlinux

$(BUILD)/linux/arch/x86/boot/bzImage: $(BUILD)/linux/vmlinux
	$(LINUX_KERNEL_MAKE) bzImage

$(BUILD)/bzImage: $(BUILD)/linux/arch/x86/boot/bzImage
	cp $< $@

$(BUILD)/install/linux/include: $(BUILD)/linux/vmlinux
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE)  INSTALL_HDR_PATH=$(@D) headers_install

$(BUILD)/install/linux/lib: $(BUILD)/linux/vmlinux
	mkdir -p $@ && rm -rf $@/* && mkdir -p $@/modules $@/firmware
	$(LINUX_KERNEL_MAKE) modules
	$(LINUX_KERNEL_MAKE) INSTALL_MOD_PATH=$(BUILD)/install/linux modules_install
	$(LINUX_KERNEL_MAKE) INSTALL_FW_PATH=$(BUILD)/install/linux/lib/firmware firmware_install

$(BUILD)/install/linux: $(BUILD)/install/linux/include $(BUILD)/install/linux/lib

################################################################################
# glibc                                                                        #
################################################################################

$(BUILD)/glibc/Makefile: $(SRC)/glibc $(BUILD)/install/linux/include
	mkdir -p $(@D) && rm -rf $(@D)/*
	# TODO: install the actuall headers somewhere
	$(SRC)/glibc/configure \
		--prefix= \
		--with-headers="$(BUILD)/install/linux/include" \
		--without-gd \
		--without-selinux \
		--disable-werror \
		CFLAGS="-Os -s -fno-stack-protector -U_FORTIFY_SOURCE" # FIXME: what does this do ?

$(BUILD)/glibc: $(BUILD)/glibc/Makefile
	$(MAKE) -C $(BUILD)/glibc -j $(NUM_JOBS)

$(BUILD)/install/glibc:
	$(MAKE) -C $(BUILD)/glibc DESTDIR=$@ -j $(NUM_JOBS)

# FIXME: this is actually our sysroot isn't it ?
$(BUILD)/prepared/glibc: $(BUILD)/install/linux
	mkdir -p $@ && rm -rf $@/*
	cp -r $(BUILD)/install/linux/* $@/
	cp -r $(BUILD)/install/glibc/* $@/
	mkdir -p $@/usr
	$(shell cd $@/usr \
		ln -s ../include include \
		ln -s ../lib lib )
	$(shell cd $@/include \
		ln -s $(BUILD)/install/linux/include/linux linux \
		ln -s $(BUILD)/install/linux/include/asm asm \
		ln -s $(BUILD)/install/linux/include/asm-generic asm-generic \
		ln -s $(BUILD)/install/linux/include/mtd mtd )

################################################################################
# busybox                                                                      #
################################################################################

GLIBC_PREPARED_ESCAPED=$(subst /,\/,$(subst \,\\,$(BUILD)/prepared/glibc))

$(BUILD)/busybox/.config: $(SRC)/busybox
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox defconfig -j $(NUM_JOBS)
	sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" "$@"
	#sed -i "s/CONFIG_SYSROOT=""/CONFIG_SYSROOT="$(GLIBC_PREPARED_ESCAPED)"/" $@
	echo CONFIG_SYSROOT="$(GLIBC_PREPARED_ESCAPED)" >> $@ # FIXME: hacky
	#$(shell cd $(@D) && sed -i "s/.\*CONFIG_INETD.\*/CONFIG_INETD=n/" .config)
	#sed -i "s/.*CONFIG_SYSROOT.*/CONFIG_SYSROOT="$(GLIBC_PREPARED_ESCAPED)"/" $@


$(BUILD)/busybox/busybox: $(BUILD)/busybox/.config $(BUILD)/prepared/glibc
	$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox all -j $(NUM_JOBS)

################################################################################
# initrd.img                                                                   #
################################################################################

$(BUILD)/initrd.img: $(BUILD)/initrd
	$(shell cd $< && find . | cpio -o -H newc | gzip > $@ )

$(BUILD)/initrd: $(BUILD)/busybox/busybox $(SRC)/initfs/init
	mkdir -p $@/bin
	#mkdir -p $@/boot
	mkdir -p $@/dev
	#mkdir -p $@/etc
	mkdir -p $@/lib/x86_64-linux-gnu
	mkdir -p $@/lib64
	#mkdir -p $@/mnt
	#mkdir -p $@/root
	mkdir -p $@/sbin
	#mkdir -p $@/tmp
	mkdir -p $@/usr
	cp $(BUILD)/busybox/busybox $@/bin/busybox
	chmod +x $@/bin/busybox
	# FIXME: borrowing the init file from the rootfs
	cp $(SRC)/initfs/init $@/init
	chmod +x $@/init
	# FIXME: "borrowing" some libraries for the time being ( 'ldd build/busybox/busybox' )
	cp /lib/x86_64-linux-gnu/libm.so.6 $@/lib/x86_64-linux-gnu/libm.so.6
	cp /lib/x86_64-linux-gnu/libc.so.6 $@/lib/x86_64-linux-gnu/libc.so.6
	cp /lib64/ld-linux-x86-64.so.2 $@/lib64/ld-linux-x86-64.so.2

################################################################################
#                                                                              #
################################################################################
