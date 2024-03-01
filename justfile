src := `pwd`
kernel_version := "6.7.6"
busybox_version := "1.36.1"
dash_version := "0.5.12"
limine_version := "7.0.5"
llvm_version := "17.0.6"
kernel_sources := src / "sources/linux/linux-" + kernel_version
busybox_sources := src / "sources/busybox/busybox-" + busybox_version
dash_sources := src / "sources/dash/dash-" + dash_version
limine_sources := src / "sources/limine/limine-" + limine_version
llvm_bin := src / "sources/llvm/llvm-" + llvm_version + "-x86_64/bin/"
config_script := src / "scripts/config"
work_dir := src / "work"
rootfs := work_dir / "rootfs"
isoimage := work_dir / "isoimage"
system_target := src / "target/x86_64-unknown-linux-gnu/release"

all: prepare configure build

build: build-all pack

pack: create-rootfs create-new-rootfs create-iso

prepare:
    rye sync
    rye run sources

configure: _configure-kernel _configure-busybox _configure-dash _configure-limine

_configure-kernel:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ kernel_sources }}"

    make ARCH=x86_64 LLVM="{{ llvm_bin }}" defconfig

    {{ config_script }} --enable LTO_CLANG_THIN                 # Enables thin lto with clang
    {{ config_script }} --enable CONFIG_KERNEL_ZSTD             # Enable zstd compression
    {{ config_script }} --enable CONFIG_FB                      # Enable zstd compression
    {{ config_script }} --enable CONFIG_FB_VESA                 # Enable zstd compression
    {{ config_script }} --enable CONFIG_FB_EFI                  # Enable zstd compression
    {{ config_script }} --enable CONFIG_FB_CORE                 # Enable zstd compression
    {{ config_script }} --enable CONFIG_FRAMEBUFFER_CONSOLE     # Enable zstd compression

    make olddefconfig

_configure-busybox:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ busybox_sources }}"

    make allnoconfig

    {{ config_script }} --set-str EXTRA_CFLAGS "-O2"
    {{ config_script }} --enable STATIC
    {{ config_script }} --enable INIT
    {{ config_script }} --enable FEATURE_USE_INITTAB
    {{ config_script }} --disable SH_IS_ASH
    {{ config_script }} --enable SH_IS_NONE
    {{ config_script }} --enable CTTYHACK
    {{ config_script }} --enable MOUNT
    {{ config_script }} --enable CP
    {{ config_script }} --enable MKDIR
    {{ config_script }} --enable SWITCH_ROOT
    {{ config_script }} --enable LS
    {{ config_script }} --enable DU
    {{ config_script }} --enable WHICH
    {{ config_script }} --enable DMESG
    {{ config_script }} --enable LESS

_configure-dash:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ dash_sources }}"

    autoreconf -fiv
    ./configure --enable-static CFLAGS="-O2"

_configure-limine:
    cd "{{ limine_sources }}" && ./configure --enable-uefi-x86-64 --enable-bios-cd --enable-uefi-cd --enable-bios

build-all: _build-linux _build-busybox _build-dash _build-limine build-system

_build-linux:
    cd "{{ kernel_sources }}" && make bzImage -j$(nproc)

_build-busybox:
    cd "{{ busybox_sources }}" && make busybox -j$(nproc)

_build-dash:
    cd "{{ dash_sources }}" && make

_build-limine:
    cd "{{ limine_sources }}" && make

build-system:
    cargo build --release --target x86_64-unknown-linux-gnu

create-rootfs:
    #!/usr/bin/env bash
    set -euxo pipefail

    # Remove old rootfs if it exists
    rm -rf "{{ rootfs }}"
    rm -rf "{{ work_dir }}"/rootfs.cpio.zst

    # Go into busybox directory
    cd "{{ busybox_sources }}"

    # Create all the symlinks
    make CONFIG_PREFIX="{{ rootfs }}" install

    # Enter rootfs
    cd "{{ rootfs }}"

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
    cp "{{ src }}"/init .
    cp "{{ src }}"/inittab etc/inittab

    # Copy shell
    cp "{{ dash_sources }}"/src/dash bin/sh

    # Copy system manager files
    mkdir system
    cp "{{ system_target }}"/init system/init
    cp "{{ system_target }}"/raminit system/raminit
    cp "{{ system_target }}"/uname system/uname
    cp "{{ system_target }}"/clear system/clear

    # Strip everything
    # strip --strip-all $ROOTFS/bin/* $ROOTFS/sbin/*

    # Pack initramfs
    find . | bsdcpio -R root:root -H newc -o | zstd -22 --ultra --long --quiet --stdout >"{{ work_dir }}"/rootfs.cpio.zst

create-new-rootfs:
    #!/usr/bin/env bash
    set -euxo pipefail

    rm -rf work/newrootfs

    mkdir -p work/newrootfs
    cd work/newrootfs
    
    mkdir dev
    mkdir proc
    mkdir sys
    mkdir tmp

    mkdir system
    cp "{{ system_target }}"/raminit system/raminit
    cp "{{ dash_sources }}"/src/dash system/sh

    find . | bsdcpio -R root:root -H newc -o | zstd -22 --ultra --long --quiet --stdout >"{{ work_dir }}"/newrootfs.cpio.zst

create-iso:
    # Remove old isoimage if it exists
    rm -rf "{{ isoimage }}"
    rm -rf woven.iso

    # Create directory for boot files
    mkdir -p "{{ isoimage }}"/boot

    # Copy the actual kernel
    cp "{{ kernel_sources }}"/arch/x86/boot/bzImage "{{ isoimage }}"/boot/kernel.zst

    # Copy the initramfs image
    cp "{{ work_dir }}"/rootfs.cpio.zst "{{ isoimage }}"/boot/rootfs.zst
    cp "{{ work_dir }}"/newrootfs.cpio.zst "{{ isoimage }}"/boot/newrootfs.zst

    # Copy all limine stuff
    cp "{{ limine_sources }}"/bin/limine-uefi-cd.bin "{{ isoimage }}"/boot
    cp "{{ limine_sources }}"/bin/limine-bios-cd.bin "{{ isoimage }}"/boot
    cp "{{ limine_sources }}"/bin/limine-bios.sys "{{ isoimage }}"/boot
    cp limine.cfg "{{ isoimage }}"/boot

    mkdir -p "{{ isoimage }}"/EFI/BOOT
    cp "{{ limine_sources }}"/bin/BOOTX64.EFI "{{ isoimage }}"/EFI/BOOT

    # Create iso
    xorriso -as mkisofs -b boot/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --efi-boot boot/limine-uefi-cd.bin \
        -efi-boot-part --efi-boot-image --protective-msdos-label \
        "{{ isoimage }}" -o "{{ src }}"/woven.iso

    # Ensure the iso is bootable
    "{{ limine_sources }}"/bin/limine bios-install woven.iso

qemu:
    scripts/qemu.sh
