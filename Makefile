#!/usr/bin/make -f

# BIG LIST OF TODO AND FIXME
# TODO: similar naming convention (src/kernel vs build/linux)
# TODO: Macros / Functions to make somewhat more readable code for the downloads
# 	alternative, makepkg implementation

################################################################################
# Variables                                                                    #
################################################################################

SRC ?=$(PWD)/src
BUILD ?=$(PWD)/build
DOCS ?=$(PWD)/docs

# Optimize for size, strip, protect against bad implementations
CFLAGS ?=-Os -s -U_FORTIFY_SOURCE

NUM_JOBS=8

MAKE=make -j $(NUM_JOBS)

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
qemu: $(BUILD)/pigeon_linux_live.iso
	# if you get a "write error no space left error" throw more ram at it
	qemu-system-x86_64 -m 64M -cdrom $< -boot d -vga std

################################################################################
# Source downloading                                                           #
################################################################################

# linux kernel

LINUX_KERNEL_DOWNLOAD_FILE=linux-4.4.52.tar.xz
LINUX_KERNEL_DOWNLOAD_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/$(LINUX_KERNEL_DOWNLOAD_FILE)

$(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE):
	rm -rf $@ && wget $(LINUX_KERNEL_DOWNLOAD_URL) -O $@

$(SRC)/kernel: $(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# glibc

GLIBC_DOWNLOAD_FILE=glibc-2.25.tar.xz
GLIBC_DOWNLOAD_URL=https://ftp.gnu.org/gnu/libc/$(GLIBC_DOWNLOAD_FILE)

$(SRC)/$(GLIBC_DOWNLOAD_FILE):
	rm -rf $@ && wget $(GLIBC_DOWNLOAD_URL) -O $@

$(SRC)/glibc: $(SRC)/$(GLIBC_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# busybox

BUSYBOX_DOWNLOAD_FILE=busybox-1.26.2.tar.bz2
BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/$(BUSYBOX_DOWNLOAD_FILE)

$(SRC)/$(BUSYBOX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BUSYBOX_DOWNLOAD_URL) -O $@

$(SRC)/busybox: $(SRC)/$(BUSYBOX_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# syslinux

SYSLINUX_DOWNLOAD_FILE=syslinux-6.03.tar.xz
SYSLINUX_DOWNLOAD_URL=http://kernel.org/pub/linux/utils/boot/syslinux/$(SYSLINUX_DOWNLOAD_FILE)

$(SRC)/$(SYSLINUX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(SYSLINUX_DOWNLOAD_URL) -O $@

$(SRC)/syslinux: $(SRC)/$(SYSLINUX_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# sinit (suckless init MIT license)

SINIT_DOWNLOAD_FILE=sinit-1.0.tar.bz2
SINIT_DOWNLOAD_URL=http://git.suckless.org/sinit/snapshot/$(SINIT_DOWNLOAD_FILE)

$(SRC)/$(SINIT_DOWNLOAD_FILE):
	rm -rf $@ && wget $(SINIT_DOWNLOAD_URL) -O $@

$(SRC)/sinit: $(SRC)/$(SINIT_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# ubase (unportable base)

# FIXME: download link would be much better
$(SRC)/ubase:
	rm -rf $@ && cd $(SRC) && git clone http://git.suckless.org/ubase

# kbd (linux keyboard tools)
KBD_DOWNLOAD_FILE=kbd-2.0.4.tar.xz
KBD_DOWNLOAD_URL=https://www.kernel.org/pub/linux/utils/kbd/$(KBD_DOWNLOAD_FILE)

$(SRC)/$(KBD_DOWNLOAD_FILE):
	rm -rf $@ && wget $(KBD_DOWNLOAD_URL) -O $@

$(SRC)/kbd: $(SRC)/$(KBD_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

################################################################################
# Linux kernel                                                                 #
################################################################################

LINUX_KERNEL_MAKE=$(MAKE) -C $(SRC)/kernel O=$(BUILD)/linux
KERNEL=$(BUILD)/linux/arch/x86/boot/bzImage

# Generate the default config for the kernel
$(BUILD)/linux/.config: $(SRC)/kernel
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(LINUX_KERNEL_MAKE) defconfig
	# Enable VESA framebuffer support
	cd $(@D) && sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" .config
	touch $@

# generate the kernel in the compressed self-extracting bzImage format
$(KERNEL): $(BUILD)/linux/.config
	$(LINUX_KERNEL_MAKE) bzImage

# install the kernel headers
$(BUILD)/install/linux/usr/include: $(BUILD)/linux/.config
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

$(BUILD)/install/linux: $(BUILD)/install/linux/usr/include $(BUILD)/install/linux/lib
	touch $@

################################################################################
# glibc                                                                        #
################################################################################

# configure glibc for compile
$(BUILD)/glibc/Makefile: $(SRC)/glibc $(BUILD)/install/linux
	mkdir -p $(@D) && rm -rf $(@D)/*
	cd "$(@D)" ; $(SRC)/glibc/configure \
		--prefix= \
		--with-headers="$(BUILD)/install/linux/usr/include" \
		--with-kernel=4.0.0 \
		--without-gd \
		--without-selinux \
		--disable-werror \
		--enable-add-ons \
		--enable-stack-protector \
		CFLAGS="$(CFLAGS)" && touch $@

# build glibc
$(BUILD)/glibc: $(BUILD)/glibc/Makefile
	$(MAKE) -C $(BUILD)/glibc && touch $@

# install glibc
$(BUILD)/install/glibc: $(BUILD)/glibc
	$(MAKE) -C $(BUILD)/glibc DESTDIR=$@ install && touch $@

################################################################################
# sysroot                                                                      #
################################################################################

SYSROOT=$(BUILD)/sysroot

# create a sysroot (headers and libraries)
$(SYSROOT): $(BUILD)/install/linux $(BUILD)/install/glibc
	rm -rf $@/ && mkdir -p $@
	rsync -a $(BUILD)/install/glibc/ $@/
	mkdir -p $@/usr
	cd $@/usr ; \
		ln -s ../include include ; \
		ln -s ../lib lib
	#rsync -a $(BUILD)/install/linux/ $@/
	cp -r $(BUILD)/install/linux/usr/include/* $@/usr/include/
	cp -r $(BUILD)/install/linux/lib/* $@/lib/
	touch $@

################################################################################
# busybox                                                                      #
################################################################################

# Escape / and \ because sed uses them for magic
SYSROOT_ESCAPED=$(subst /,\/,$(subst \,\\,$(SYSROOT)))

# TODO: remove as many flags and recompile busybox to see which are actually needed

BUSYBOX_MAKE=$(MAKE) -C $(SRC)/busybox O=$(BUILD)/busybox CFLAGS="$(CFLAGS) -fomit-frame-pointer"

$(BUILD)/busybox/.config: $(SRC)/busybox $(SYSROOT)
	mkdir -p $(@D) && rm -rf $(@D)/*
	$(BUSYBOX_MAKE) defconfig
	# enable static linking for the time being
	# cd $(@D) && sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/g' .config
	# dynamic linking rules!
	##
	cd $(@D) && sed -i 's/.*CONFIG_SYSROOT.*/CONFIG_SYSROOT="$(SYSROOT_ESCAPED)"/g' .config

$(BUILD)/busybox: $(BUILD)/busybox/.config $(SYSROOT)
	$(BUSYBOX_MAKE) all && touch $@

$(BUILD)/install/busybox: $(BUILD)/busybox
	$(BUSYBOX_MAKE) CONFIG_PREFIX=$@ install

################################################################################
# sinit                                                                        #
################################################################################

$(BUILD)/sinit: $(SRC)/sinit $(SYSROOT)
	rm -rf $@ && mkdir -p $@
	rsync -avr $</ $@/
	$(MAKE) -C $(BUILD)/sinit all CFLAGS="$(CFLAGS) --sysroot=$(SYSROOT)" && touch $@

$(BUILD)/install/sinit: $(BUILD)/sinit
	rm -rf $@ && mkdir -p $@
	$(MAKE) -C $(BUILD)/sinit PREFIX=/usr DESTDIR=$@ install && touch $@

################################################################################
# ubase                                                                        #
################################################################################

$(BUILD)/ubase: $(SRC)/ubase $(SYSROOT)
	rm -rf $@ && mkdir -p $@
	rsync -avr $</ $@/
	$(MAKE) -C $(BUILD)/ubase all CFLAGS="$(CFLAGS) --sysroot=$(SYSROOT)" && touch $@

$(BUILD)/install/ubase: $(BUILD)/ubase
	rm -rf $@ && mkdir -p $@
	$(MAKE) -C $(BUILD)/sinit PREFIX=/usr DESTDIR=$@ install && touch $@

################################################################################
# kbd                                                                          #
################################################################################

################################################################################
# rootfs                                                                       #
################################################################################

$(BUILD)/rootfs: $(SRC)/initfs $(BUILD)/install/busybox $(BUILD)/install/sinit \
		$(BUILD)/install/ubase $(SYSROOT)
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
	install -m 0644 $(SRC)/filesystem/etc/os-version $@/etc/os-version
	install -m 0644 $(SRC)/filesystem/etc/passwd $@/etc/passwd
	install -m 0644 $(SRC)/filesystem/etc/securetty $@/etc/securetty
	install -m 0600 $(SRC)/filesystem/etc/shadow $@/etc/shadow
	install -m 0644 $(SRC)/filesystem/etc/shells $@/etc/shells
	install -d -m 0755 $@/home
	install -d -m 0755 $@/lib
	install -d -m 0755 $@/lib/modules
	install -d -m 0755 $@/lib32
	ln -s lib $@/lib64
	install -d -m 0755 $@/mnt
	install -d -m 0755 $@/opt
	install -d -m 0755 $@/opt/bin
	install -d -m 0755 $@/opt/sbin
	install -d -m 0555 $@/proc
	install -d -m 0750 $@/root
	install -d -m 0755 $@/run
	install -d -m 0755 $@/sbin
	install -d -m 0555 $@/sys
	install -d -m 1777 $@/tmp
	install -d -m 0755 $@/usr
	install -d -m 0755 $@/usr/bin
	install -d -m 0755 $@/usr/include
	install -d -m 0755 $@/usr/lib
	install -d -m 0755 $@/usr/lib32
	ln -s lib $@/usr/lib64
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
	ln -s spool/mail $@/var/mail
	install -d -m 0755 $@/var/run
	install -d -m 0755 $@/var/run/utmp
	install -d -m 0755 $@/var/spool
	install -d -m 1777 $@/var/spool/mail
	install -d -m 1777 $@/var/tmp
	# copy all the files in the sysroot over
	#rsync -avr $(SYSROOT)/ $@/
	cp $(SYSROOT)/lib/ld-linux* $@/lib
	cp $(SYSROOT)/lib/libm.so.6 $@/lib
	cp $(SYSROOT)/lib/libc.so.6 $@/lib
	cp $(SYSROOT)/lib/libresolv.so.2 $@/lib
	cp $(SYSROOT)/lib/libnss_dns.so.2 $@/lib
	rsync -avr $(BUILD)/install/busybox/ $@/
	rsync -avr $(BUILD)/install/sinit/ $@/
	rsync -avr $(BUILD)/install/ubase/ $@/
	# link the init system
	ln -s usr/bin/sinit $@/init
	ln -s ../usr/bin/sinit $@/sbin/init
	# update the date on the directory itself
	touch $@

################################################################################
# initrd.cpio.gz                                                               #
################################################################################

$(BUILD)/initramfs: $(SRC)/initfs $(BUILD)/rootfs
	rm -rf $@ && mkdir -p $@
	rsync -avr $(BUILD)/rootfs/ $@/
	rsync -avr $(SRC)/initfs/ $@/
	touch $@

$(BUILD)/initrd.cpio.gz: $(BUILD)/initramfs
	# pack the initramfs and make everything be owned by root
	$(shell cd $< && find . | cpio -o -H newc -R 0:0 | gzip > $@ )

################################################################################
# live iso generation                                                          #
################################################################################

$(BUILD)/iso: $(BUILD)/initrd.cpio.gz $(KERNEL) $(SRC)/syslinux \
		$(SRC)/syslinux.cfg
	rm -rf $@ && mkdir -p $@
	cp $(BUILD)/initrd.cpio.gz $@/initrd.cpio.gz
	cp $(KERNEL) $@/kernel
	cp $(SRC)/syslinux/bios/core/isolinux.bin $@/isolinux.bin
	cp $(SRC)/syslinux/bios/com32/elflink/ldlinux/ldlinux.c32 $@/ldlinux.c32
	mkdir -p $@/efi/boot # TODO: UEFI support
	#echo 'default kernel  initrd=initrd.cpio.gz vga=ask' > $@/syslinux.cfg
	cp $(SRC)/syslinux.cfg $@/
	touch $@

$(BUILD)/pigeon_linux_live.iso: $(BUILD)/iso
	cd $< ; genisoimage \
		-J \
		-r \
		-o $@ \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$(BUILD)/iso

################################################################################
#                                                                              #
################################################################################
