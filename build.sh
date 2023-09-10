#!/bin/sh

set -e

KERNEL_VERSION=6.5.2
BUSYBOX_VERSION=1.36.1
SYSLINUX_VERSION=6.03
SRC_DIR=$PWD
WORK_DIR=$SRC_DIR/work
ROOTFS=$WORK_DIR/rootfs
ISOIMAGE=$WORK_DIR/isoimage

KERNEL_SOURCES=$SRC_DIR/sources/linux/linux-${KERNEL_VERSION}
BUSYBOX_SOURCES=$SRC_DIR/sources/busybox/busybox-${BUSYBOX_VERSION}
SYSLINUX_SOURCES=$SRC_DIR/sources/syslinux/syslinux-${SYSLINUX_VERSION}
SYSTEM_MANAGER_SOURCES=$SRC_DIR/system_manager
SYSTEM_MANAGER_TARGET=$SYSTEM_MANAGER_SOURCES/target/x86_64-unknown-linux-gnu/release

build_kernel() {
    # Go into the linux directory
    cd $KERNEL_SOURCES

    # Make sure everything is squeaky clean
    make mrproper

    # Create a default config for amd64 that uses clang to build
    make ARCH=x86_64 LLVM=1 defconfig

    # Configure the kernel before building
    ./scripts/config --enable LTO_CLANG_FULL     # Enables full lto with clang
    ./scripts/config --enable CONFIG_EFI_STUB    # Enable efi stub to allow booting in eufi systems
    ./scripts/config --enable CONFIG_KERNEL_ZSTD # Enable zstd compression
    ./scripts/config --enable CONFIG_FB_VESA     # Enable the VESA framebuffer for graphics support.

    # Build the kernel
    # ARCH=x86_64 - Makes sure we build for the correct architecture
    # LLVM=1 - Uses clang and other llvm utilities instead of gcc and gnu's binutils
    # KCFLAGS="-O2" - Additional compiler flags, -O2 optimizes for performance
    make ARCH=x86_64 LLVM=1 KCFLAGS="-O2" bzImage

    # Go back to src before exiting
    cd $SRC_DIR
}

build_busybox() {
    # Go into busybox directory
    cd $BUSYBOX_SOURCES

    # Make sure everything is clean
    make distclean

    # Create a default config
    make defconfig

    # Configure busybox before building
    sed -i "s|.*CONFIG_EXTRA_CFLAGS.*|CONFIG_EXTRA_CFLAGS=\"-O2\"|" .config # Use compiler optimizations
    sed -i "s|.*CONFIG_STATIC.*|CONFIG_STATIC=y|" .config                   # Create a static build
    echo "CONFIG_STATIC_LIBGCC=y" >>.config                                 # Use a static copy of libgcc

    # Build busybox
    make busybox

    # Go back to src before exiting
    cd $SRC_DIR
}

build_system_manager() {
    cd $SYSTEM_MANAGER_SOURCES

    cargo build --release --target x86_64-unknown-linux-gnu -Zbuild-std=core
    objcopy -R .eh_frame -R .comment $SYSTEM_MANAGER_TARGET/init

    cd $SRC_DIR
}

create_rootfs() {
    # Remove old rootfs if it exists
    rm -rf $ROOTFS
    rm -rf $WORK_DIR/rootfs.cpio.zst

    # Go into busybox directory
    cd $BUSYBOX_SOURCES

    # Create all the symlinks
    make CONFIG_PREFIX=$ROOTFS install

    # Enter rootfs
    cd $ROOTFS

    # Create basic filesystem
    mkdir dev
    mkdir etc
    mkdir lib
    mkdir proc
    mkdir root
    mkdir sys
    mkdir tmp
    mkdir var
    mkdir mnt

    # Copy init files
    cp $SRC_DIR/init .
    cp $SRC_DIR/inittab etc/inittab

    # Copy system manager files
    mkdir system_manager
    objcopy -R .eh_frame -R .comment $SYSTEM_MANAGER_TARGET/init system_manager/init

    rm linuxrc

    # Strip everything
    strip --strip-all $ROOTFS/bin/* $ROOTFS/sbin/*

    # Pack initramfs
    find . | bsdcpio -R root:root -H newc -o | zstd -22 --ultra --long --quiet --stdout >$WORK_DIR/rootfs.cpio.zst

    # Go back to src before exiting
    cd $SRC_DIR
}

create_iso() {
    # Remove old isoimage if it exists
    rm -rf $ISOIMAGE
    rm -rf cutiepie.iso

    # Create directory for boot files
    mkdir -p $ISOIMAGE/boot

    # Copy the actual kernel
    cp $KERNEL_SOURCES/arch/x86/boot/bzImage $ISOIMAGE/boot/kernel.zst

    # Copy the initramfs image
    cp $WORK_DIR/rootfs.cpio.zst $ISOIMAGE/boot/rootfs.zst

    # Create a directry for all the syslinux files
    mkdir -p $ISOIMAGE/boot/syslinux

    # Copy all the syslinux files
    cp $SYSLINUX_SOURCES/bios/core/isolinux.bin $ISOIMAGE/boot/syslinux                 # Sylinux boot files
    cp $SYSLINUX_SOURCES/bios/com32/elflink/ldlinux/ldlinux.c32 $ISOIMAGE/boot/syslinux # Helper file required by syslinux
    cp $SYSLINUX_SOURCES/bios/com32/libutil/libutil.c32 $ISOIMAGE/boot/syslinux         # Helper file required by menu.c32
    cp $SYSLINUX_SOURCES/bios/com32/menu/menu.c32 $ISOIMAGE/boot/syslinux               # File containing the syslinux text menu
    cp $SRC_DIR/syslinux.cfg $ISOIMAGE/boot/syslinux/                                   # Sylinux config file

    # Now we generate 'hybrid' ISO image file which can also be used on
    # USB flash drive, e.g. 'dd if=minimal_linux_live.iso of=/dev/sdb'.
    xorriso -as mkisofs \
        -isohybrid-mbr $SRC_DIR/sources/syslinux/syslinux-*/bios/mbr/isohdpfx.bin \
        -c boot/syslinux/boot.cat \
        -b boot/syslinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -o $SRC_DIR/cutiepie.iso \
        $ISOIMAGE

    # xorriso -as mkisofs \
    #     -isohybrid-mbr $WORK_DIR/syslinux/syslinux-*/bios/mbr/isohdpfx.bin \
    #     -c boot/boot.cat \
    #     -e boot/uefi.img \
    #     -no-emul-boot \
    #     -isohybrid-gpt-basdat \
    #     -o $SRC_DIR/minimal_linux_live.iso \
    #     $ISOIMAGE

    cd $SRC_DIR

}

DOWNLOAD_SOURCES=true
BUILD_KERNEL=true
BUILD_BUSYBOX=true

while getopts "skb" arg; do
    case ${arg} in
    s)
        DOWNLOAD_SOURCES=false
        ;;
    k)
        BUILD_KERNEL=false
        ;;
    b)
        BUILD_BUSYBOX=false
        ;;
    esac
done

if $DOWNLOAD_SOURCES; then
    rm -rf $WORK_DIR
    python download_and_extract.py
else
    echo "Skipping sources download"
fi

if $BUILD_KERNEL; then
    build_kernel
else
    echo "Skipping kernel build"
fi

if $BUILD_BUSYBOX; then
    build_busybox
else
    echo "Skipping busybox build"
fi

build_system_manager
create_rootfs
create_iso
