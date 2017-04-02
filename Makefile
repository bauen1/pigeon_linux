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

# Optimize, strip, protect against bad implementations
CFLAGS ?=-O3 -s -U_FORTIFY_SOURCE

NUM_JOBS=8

MAKE=make -j $(NUM_JOBS)

################################################################################
# Special Targets                                                              #
################################################################################

.DEFAULT: help
.PHONY: info
info:
	@echo "targets:         "
	@echo ""
	@echo "	all             build the livecd iso file"
	@echo ""
	@echo "	clean           clean build/*"
	@echo "	clean_src       clean all downloads"
	@echo ""
	@echo "	qemu            run qemu with the livecd"
	@echo ""

.PHONY: all
all: $(BUILD)/pigeon_linux_live.iso

.PHONY: clean
clean:
	rm -rf $(BUILD)/*

.PHONY: clean_src
clean_src:
	rm -rf $(SRC)/linux-*.tar.xz      $(SRC)/linux
	rm -rf $(SRC)/glibc-*.tar.xz      $(SRC)/glibc
	rm -rf $(SRC)/busybox-*.tar.bz2   $(SRC)/busybox
	rm -rf $(SRC)/syslinux-*.tar.xz   $(SRC)/syslinux
	rm -rf $(SRC)/sinit-*tar.bz2      $(SRC)/sinit
	rm -rf $(SRC)/kbd-*.tar.xz        $(SRC)/kbd

.POHNY: qemu
qemu: $(BUILD)/pigeon_linux_live.iso
	# if you get a "write error no space left error", throw more ram at it
	qemu-system-x86_64 -m 64M -cdrom $< -boot d -vga std

################################################################################
# Source downloading                                                           #
################################################################################

# TODO: signature and hash checking

# linux kernel

LINUX_KERNEL_VERSION=4.9.20
LINUX_KERNEL_DOWNLOAD_FILE=linux-$(LINUX_KERNEL_VERSION).tar.xz
LINUX_KERNEL_DOWNLOAD_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/$(LINUX_KERNEL_DOWNLOAD_FILE)

$(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE):
	rm -rf $@ && wget $(LINUX_KERNEL_DOWNLOAD_URL) -O $@

$(SRC)/linux: $(SRC)/$(LINUX_KERNEL_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# glibc

GLIBC_VERSION=2.25
GLIBC_DOWNLOAD_FILE=glibc-$(GLIBC_VERSION).tar.xz
GLIBC_DOWNLOAD_URL=https://ftp.gnu.org/gnu/libc/$(GLIBC_DOWNLOAD_FILE)

$(SRC)/$(GLIBC_DOWNLOAD_FILE):
	rm -rf $@ && wget $(GLIBC_DOWNLOAD_URL) -O $@

$(SRC)/glibc: $(SRC)/$(GLIBC_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# busybox

BUSYBOX_VERSION=1.26.2
BUSYBOX_DOWNLOAD_FILE=busybox-$(BUSYBOX_VERSION).tar.bz2
BUSYBOX_DOWNLOAD_URL=http://busybox.net/downloads/$(BUSYBOX_DOWNLOAD_FILE)

$(SRC)/$(BUSYBOX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(BUSYBOX_DOWNLOAD_URL) -O $@

$(SRC)/busybox: $(SRC)/$(BUSYBOX_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# syslinux

SYSLINUX_VERSION=6.03
SYSLINUX_DOWNLOAD_FILE=syslinux-$(SYSLINUX_VERSION).tar.xz
SYSLINUX_DOWNLOAD_URL=http://kernel.org/pub/linux/utils/boot/syslinux/$(SYSLINUX_DOWNLOAD_FILE)

$(SRC)/$(SYSLINUX_DOWNLOAD_FILE):
	rm -rf $@ && wget $(SYSLINUX_DOWNLOAD_URL) -O $@

$(SRC)/syslinux: $(SRC)/$(SYSLINUX_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# sinit (suckless init MIT license)

SINIT_VERSION=1.0
SINIT_DOWNLOAD_FILE=sinit-$(SINIT_VERSION).tar.bz2
SINIT_DOWNLOAD_URL=http://git.suckless.org/sinit/snapshot/$(SINIT_DOWNLOAD_FILE)

$(SRC)/$(SINIT_DOWNLOAD_FILE):
	rm -rf $@ && wget $(SINIT_DOWNLOAD_URL) -O $@

$(SRC)/sinit: $(SRC)/$(SINIT_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

# kbd (linux keyboard tools)

KBD_VERSION=2.0.4
KBD_DOWNLOAD_FILE=kbd-$(KBD_VERSION).tar.xz
KBD_DOWNLOAD_URL=https://www.kernel.org/pub/linux/utils/kbd/$(KBD_DOWNLOAD_FILE)

$(SRC)/$(KBD_DOWNLOAD_FILE):
	rm -rf $@ && wget $(KBD_DOWNLOAD_URL) -O $@

$(SRC)/kbd: $(SRC)/$(KBD_DOWNLOAD_FILE)
	rm -rf $@ && mkdir -p $@
	tar -xvf $< -C $@ --strip-components=1 && touch $@

################################################################################
# Linux kernel                                                                 #
################################################################################

LINUX_KERNEL_MAKE=$(MAKE) -C $(SRC)/linux O=$(BUILD)/linux
KERNEL=$(BUILD)/linux/arch/x86/boot/bzImage

# Generate the default config for the kernel
$(BUILD)/linux/.config: $(SRC)/linux
	rm -rf $(@D) && mkdir -p $(@D) # FORCE a rebuild of everything depending on this in any way
	$(LINUX_KERNEL_MAKE) defconfig
	# Enable VESA framebuffer support
	cd $(@D) && sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" .config
	# disable the boot logo
	cd $(@D) && sed -i "s/.*CONFIG_LOGO_LINUX_CLUT224.*/\\# CONFIG_LOGO_LINUX_CLUT224 is not set/" .config
	touch $@

# compile the kernel and modules
$(KERNEL): $(BUILD)/linux/.config
	$(LINUX_KERNEL_MAKE) bzImage
	$(LINUX_KERNEL_MAKE) modules

# install the kernel headers
$(BUILD)/install/linux/usr/include: $(KERNEL) # FIXME: $(BUILD)/linux/.config should be enough
	rm -rf $@ && mkdir -p $@
	$(LINUX_KERNEL_MAKE) INSTALL_HDR_PATH=$(@D) headers_install

# install all the kernel modules
$(BUILD)/install/linux/usr/lib/modules: $(KERNEL)
	rm -rf $@ && mkdir -p $@
	$(LINUX_KERNEL_MAKE) INSTALL_MOD_PATH=$(BUILD)/install/linux/usr \
		modules_install
	sleep 3 && touch $@

# install all the kernel firmware
$(BUILD)/install/linux/usr/lib/firmware: $(KERNEL) # FIXME: $(BUILD)/linux/.config should be enough
	rm -rf $@ && mkdir -p $@
	$(LINUX_KERNEL_MAKE) INSTALL_FW_PATH=$(BUILD)/install/linux/usr/lib/firmware \
		firmware_install
	sleep 3 && touch $@

$(BUILD)/install/linux/usr/lib: $(BUILD)/install/linux/usr/lib/modules \
		$(BUILD)/install/linux/usr/lib/firmware
	sleep 3 && touch $@

$(BUILD)/install/linux/usr: $(BUILD)/install/linux/usr/include \
		$(BUILD)/install/linux/usr/lib
	sleep 3 && touch $@

$(BUILD)/install/linux: $(BUILD)/install/linux/usr
	sleep 3 && touch $@

################################################################################
# glibc                                                                        #
################################################################################

# configure glibc for compile
$(BUILD)/glibc/Makefile: $(SRC)/glibc $(BUILD)/install/linux
	rm -rf $(@D) && mkdir -p $(@D)
	cd "$(@D)" && $(SRC)/glibc/configure \
		--prefix=/usr \
		--libexecdir=/usr/lib \
		--with-headers="$(BUILD)/install/linux/usr/include" \
		--with-kernel=4.0.0 \
		--without-gd \
		--without-selinux \
		--disable-werror \
		--enable-add-ons \
		--enable-stack-protector \
		CFLAGS="$(CFLAGS)" \
		libc_cv_slibdir=/usr/lib # lib is symlinked to /usr/lib
	touch $@

# build glibc
$(BUILD)/glibc: $(BUILD)/glibc/Makefile
	$(MAKE) -C $(BUILD)/glibc && touch $@

# install glibc
$(BUILD)/install/glibc: $(BUILD)/glibc
	rm -rf $@ && mkdir -p $@
	$(MAKE) -C $(BUILD)/glibc DESTDIR=$@ install && touch $@

################################################################################
# sysroot                                                                      #
################################################################################

SYSROOT=$(BUILD)/sysroot

# create a sysroot (headers and libraries)
$(SYSROOT): $(BUILD)/install/linux $(BUILD)/install/glibc
	rm -rf $@/ && mkdir -p $@
	ln -s usr/bin $@/bin
	ln -s usr/sbin $@/sbin
	ln -s usr/lib $@/lib
	ln -s usr/lib $@/lib64
	mkdir -p $@/usr
	ln -s lib $@/usr/lib64
	rsync -rlpgoDvrK $(BUILD)/install/glibc/ $@/
	rsync -rlpgoDvrK $(BUILD)/install/linux/ $@/
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
	# tell busybox to use the sysroot
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
	rsync -rlpgoDvr $</ $@/
	$(MAKE) -C $(BUILD)/sinit all CFLAGS="$(CFLAGS) --sysroot=$(SYSROOT)" && touch $@

$(BUILD)/install/sinit: $(BUILD)/sinit
	rm -rf $@ && mkdir -p $@
	$(MAKE) -C $(BUILD)/sinit PREFIX=/usr DESTDIR=$@ install && touch $@

################################################################################
# kbd                                                                          #
################################################################################

$(BUILD)/kbd/Makefile: $(SRC)/kbd $(SYSROOT)
	rm -rf $(@D) && mkdir -p $(@D)
	cd $(@D) && $(SRC)/kbd/configure
		--prefix=/usr \
		--with-sysroot=$(SYSROOT) \
		--datadir=/usr/share/kbd \
		--mandir=/usr/share/man && \
	touch $@

$(BUILD)/kbd: $(BUILD)/kbd/Makefile $(SYSROOT)
	$(MAKE) -C $(BUILD)/kbd all && touch $@

$(BUILD)/install/kbd: $(BUILD)/kbd
	rm -rf $@ && mkdir -p $@
	$(MAKE) -C $(BUILD)/kbd DESTDIR=$@ install && touch $@

################################################################################
# rootfs                                                                       #
################################################################################

$(BUILD)/rootfs: $(BUILD)/install/busybox $(BUILD)/install/sinit \
		$(SYSROOT) $(BUILD)/install/kbd \
		$(BUILD)/install/linux
	rm -rf $@ && mkdir -p $@
	# Create the basic filesystem (please keep this sorted)
	ln -s usr/bin $@/bin
	install -d -m 0755 $@/boot
	install -d -m 0755 $@/dev
	install -d -m 0755 $@/dev/pts
	install -d -m 0755 $@/dev/shm
	install -d -m 0755 $@/etc
	install -d -m 0755 $@/etc/opt
	ln -s ../proc/self/mounts $@/etc/mtab
	install -d -m 0755 $@/home
	ln -s usr/lib $@/lib
	ln -s usr/lib $@/lib64
	install -d -m 0755 $@/media
	install -d -m 0755 $@/mnt
	install -d -m 0755 $@/opt
	install -d -m 0555 $@/proc
	install -d -m 0750 $@/root
	install -d -m 0755 $@/run
	ln -s usr/sbin $@/sbin
	install -d -m 0555 $@/sys
	install -d -m 1777 $@/tmp
	install -d -m 0755 $@/usr
	install -d -m 0755 $@/usr/bin
	install -d -m 0755 $@/usr/include
	install -d -m 0755 $@/usr/lib
	#install -d -m 0755 $@/usr/lib32
	ln -s lib $@/usr/lib64
	# Note: please use lib instead of libexec
	install -d -m 0755 $@/usr/local
	install -d -m 0755 $@/usr/local/bin
	install -d -m 0755 $@/usr/local/etc
	install -d -m 0755 $@/usr/local/games
	install -d -m 0755 $@/usr/local/include
	install -d -m 0755 $@/usr/local/lib
	ln -s lib $@/usr/local/lib64
	install -d -m 0755 $@/usr/local/man
	install -d -m 0755 $@/usr/local/sbin
	install -d -m 0755 $@/usr/local/share
	install -d -m 0755 $@/usr/local/src
	install -d -m 0755 $@/usr/sbin
	install -d -m 0755 $@/usr/share
	install -d -m 0755 $@/usr/share/man
	install -d -m 0755 $@/usr/share/man/man{1,2,3,4,5,6,7,8}
	install -d -m 0755 $@/usr/share/misc
	install -d -m 0755 $@/usr/src
	install -d -m 0755 $@/var
	install -d -m 0755 $@/var/cache
	install -d -m 0755 $@/var/lib
	install -d -m 0755 $@/var/lock
	install -d -m 0755 $@/var/log
	ln -s spool/mail $@/var/mail
	install -d -m 0755 $@/var/opt
	ln -s ../run $@/var/run
	install -d -m 0755 $@/var/spool
	install -d -m 0755 $@/var/spool/cron
	install -d -m 1777 $@/var/spool/mail
	install -d -m 1777 $@/var/tmp
	# install the files
	install -m 0644 $(SRC)/filesystem/etc/fstab $@/etc/fstab
	install -m 0644 $(SRC)/filesystem/etc/group $@/etc/group
	install -m 0600 $(SRC)/filesystem/etc/gshadow $@/etc/gshadow
	install -m 0644 $(SRC)/filesystem/etc/hostname $@/etc/hostname
	install -m 0644 $(SRC)/filesystem/etc/hosts $@/etc/hosts
	install -m 0644 $(SRC)/filesystem/etc/issue $@/etc/issue
	install -m 0644 $(SRC)/filesystem/etc/motd $@/etc/motd
	install -m 0644 $(SRC)/filesystem/etc/os-version $@/etc/os-version
	install -m 0644 $(SRC)/filesystem/etc/passwd $@/etc/passwd
	install -m 0644 $(SRC)/filesystem/etc/profile $@/etc/profile
	install -m 0644 $(SRC)/filesystem/etc/securetty $@/etc/securetty
	install -m 0600 $(SRC)/filesystem/etc/shadow $@/etc/shadow
	install -m 0644 $(SRC)/filesystem/etc/shells $@/etc/shells
	# copy all the needed files in the sysroot over
	cp $(SYSROOT)/usr/lib/ld-linux* $@/usr/lib
	cp $(SYSROOT)/usr/lib/libm.so.6 $@/usr/lib
	cp $(SYSROOT)/usr/lib/libc.so.6 $@/usr/lib
	cp $(SYSROOT)/usr/lib/libcrypt.so.1 $@/usr/lib
	cp $(SYSROOT)/usr/lib/libresolv.so.2 $@/usr/lib
	cp $(SYSROOT)/usr/lib/libnss_dns.so.2 $@/usr/lib
	rsync -rlpgoDvrK $(BUILD)/install/linux/ $@/
	rsync -rlpgoDvrK $(BUILD)/install/kbd/ $@/
	rsync -rlpgoDvrK $(BUILD)/install/sinit/ $@/
	# link the init system
	ln -sf usr/bin/sinit $@/init
	ln -sf ../usr/bin/sinit $@/sbin/init
	rsync -rlpgoDvr --ignore-existing $(BUILD)/install/busybox/ $@/
	rm -f $@/linuxrc
	# update the date on the directory itself
	touch $@

################################################################################
# initrd.cpio.gz                                                               #
################################################################################

INITRAMFS_LIBS=ld-linux* libm.so.6 libc.so.6

$(BUILD)/initramfs: $(BUILD)/install/busybox $(SYSROOT) $(SRC)/mkinitramfs/init
	rm -rf $@ && mkdir -p $@
	ln -s usr/bin $@/bin
	install -d -m 0755 $@/etc
	ln -s usr/lib $@/lib
	ln -s usr/lib $@/lib64
	install -d -m 0755 $@/mnt
	install -d -m 0755 $@/proc
	ln -s usr/sbin $@/sbin
	install -d -m 0755 $@/sys
	install -d -m 0755 $@/tmp
	install -d -m 0755 $@/usr
	install -d -m 0755 $@/usr/bin
	install -d -m 0755 $@/usr/lib
	ln -s lib $@/usr/lib64
	install -d -m 0755 $@/usr/sbin
	install -d -m 0755 $@/usr/share
	install -d -m 0755 $@/usr/share/man
	install -d -m 0755 $@/usr/share/man/man{1,2,3,4,5,6,7,8}
	# copy all needed libraries over
	cp $(SYSROOT)/usr/lib/$(INITRAMFS_LIBS) $@/usr/lib
	cp $(SRC)/mkinitramfs/init $@/init
	chmod +x $@/init
	cp $(BUILD)/install/busybox/bin/busybox $@/usr/bin
	chmod +x $@/usr/bin/busybox
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
	cp $(SRC)/syslinux.cfg $@/
	touch $@

$(BUILD)/pigeon_linux_live.iso: $(BUILD)/iso
	cd $< && genisoimage \
		-J \
		-r \
		-o $@ \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$<

################################################################################
#                                                                              #
################################################################################
