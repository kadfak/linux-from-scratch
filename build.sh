#!/bin/bash

set -ex

LINUX_VERSION=5.4.10
LINUX_ARCHIVE=linux-$LINUX_VERSION.tar.xz
GLIBC_VERSION=2.30
GLIBC_ARCHIVE=glibc-$GLIBC_VERSION.tar.xz
BUSYBOX_VERSION=1.31.1
BUSYBOX_ARCHIVE=busybox-$BUSYBOX_VERSION.tar.bz2
SYSLINUX_VERSION=6.03
SYSLINUX_ARCHIVE=syslinux-$SYSLINUX_VERSION.tar.xz

if [ ! -f $LINUX_ARCHIVE ]; then
    curl -O https://cdn.kernel.org/pub/linux/kernel/v5.x/$LINUX_ARCHIVE
    tar -xf $LINUX_ARCHIVE
fi

if [ ! -f $GLIBC_ARCHIVE ]; then
    curl -O http://www.nic.funet.fi/pub/gnu/ftp.gnu.org/pub/gnu/libc/$GLIBC_ARCHIVE
    tar -xf $GLIBC_ARCHIVE
fi

if [ ! -f $BUSYBOX_ARCHIVE ]; then
    curl -O https://busybox.net/downloads/$BUSYBOX_ARCHIVE
    tar -xf $BUSYBOX_ARCHIVE
fi

if [ ! -f $SYSLINUX_ARCHIVE ]; then
    curl -O https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/$SYSLINUX_ARCHIVE
    tar -xf $SYSLINUX_ARCHIVE
fi

build_busybox() {
    # Busybox dependencies:
    # linux-vdso.so.1
    # libm.so.6 => /usr/lib/libm.so.6
    # libresolv.so.2 => /usr/lib/libresolv.so.2
    # libc.so.6 => /usr/lib/libc.so.6
    # /lib64/ld-linux-x86-64.so.2 => /usr/lib64/ld-linux-x86-64.so.2

    cd busybox-$BUSYBOX_VERSION

    make distclean -j 8
    make defconfig -j 8

    sed -e "s|.*CONFIG_STATIC.*|CONFIG_STATIC=y|" -i .config
    #sed -e "s|.*CONFIG_SYSROOT.*|CONFIG_SYSROOT=\"$SYSTEM_DIR\"|" -i .config
    #sed -e "s|.*CONFIG_EXTRA_CFLAGS.*|CONFIG_EXTRA_CFLAGS=\"-L$SYSTEM_DIR/lib\"|" -i .config

    make busybox -j 8

    #sed -e "s/\/sbin/\/bin/" -i busybox.links
    #sed -e "s/\/usr\/bin/\/bin/" -i busybox.links
    #sed -e "s/\/usr\/sbin/\/bin/" -i busybox.links
    #sed -e "/linuxrc/d" -i busybox.links

    cp ../busybox.links ./

    make install -j 8

    cd ..
}

build_linux() {
    cd linux-$LINUX_VERSION
    
    make mrproper -j 8
    make defconfig -j 8
    make bzImage -j 8
    #make INSTALL_HDR_PATH=$LINUX_HEADERS_DIR headers_install -j 8

    cd ..
}

create_initramfs() {
    mkdir -p initramfs_aux
    cd initramfs_aux
    mkdir -p dev proc sys

    cp -r ../busybox-$BUSYBOX_VERSION/_install/bin ./

    cat > init << "EOF"
#!/bin/sh
dmesg -n 1
mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t sysfs none /sys
setsid cttyhack /bin/sh
EOF
    chmod +x init

    find . \
        | cpio --owner=root:root --format=newc --create \
        | xz -9 --check=none \
        > ../initramfs
    
    cd ..
    rm -rf initramfs_aux
}

create_iso() {
    rm -rf iso
    mkdir -p iso
    cd iso
    mkdir -p syslinux

    cp ../linux-$LINUX_VERSION/arch/x86/boot/bzImage ./linux
    cp ../initramfs ./initramfs
    cp ../syslinux-$SYSLINUX_VERSION/bios/core/isolinux.bin ./syslinux/
    cp ../syslinux-$SYSLINUX_VERSION/bios/com32/elflink/ldlinux/ldlinux.c32 ./syslinux

    cat > syslinux.cfg << "EOF"
PROMPT 0
DEFAULT linux
LABEL linux
LINUX linux
INITRD initramfs
APPEND quiet
EOF

    # note: boot.cat is created automatically
    xorriso \
        -as mkisofs \
        -o ../x.iso \
        -isohybrid-mbr ../syslinux-$SYSLINUX_VERSION/bios/mbr/isohdpfx.bin \
        -b syslinux/isolinux.bin \
        -c syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        ./

    cd ..
    rm -rf iso
}

#build_busybox
#build_linux
#create_initramfs
create_iso

# /linuxrc is launched on an old-style initrd, /sbin/init is launched on a
# newer-style initrd, /init is launched on an initramfs. Initrd and initramfs are
# two mechanisms with the same purpose: to mount a filesystem in RAM from which
# storage drivers can be loaded. Initrd is older, initramfs is the current
# recommended method.
# src: https://unix.stackexchange.com/questions/265092/how-can-i-check-the-first-process-that-is-run-i-can-see-both-init-and-linuxrc-i

set +ex
