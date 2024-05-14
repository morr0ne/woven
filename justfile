src := `pwd`
kernel_version := `woven-sources linux`
busybox_version := `woven-sources busybox`
dash_version := `woven-sources dash`
limine_version := `woven-sources limine`
mesa_version := `woven-sources mesa`
llvm_version := `woven-sources llvm`
kernel_sources := src / "sources/linux/linux-" + kernel_version
busybox_sources := src / "sources/busybox/busybox-" + busybox_version
dash_sources := src / "sources/dash/dash-" + dash_version
limine_sources := src / "sources/limine/limine-" + limine_version
mesa_sources := src / "sources/mesa/mesa-" + mesa_version
llvm_bin := src / "sources/llvm/llvm-" + llvm_version + "-x86_64/bin/"
config_script := src / "scripts/config"
work_dir := src / "work"
rootfs := work_dir / "rootfs"
stemfs := work_dir / "stemfs"
isoimage := work_dir / "isoimage"
system_target := src / "system/target/x86_64-unknown-linux-none/release"

all: prepare configure build-all pack

pack: create-rootfs create-stemfs

prepare:
    woven-sources
    
configure: _configure-kernel _configure-busybox _configure-dash _configure-limine

_configure-kernel:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ kernel_sources }}"
    
    make ARCH=x86_64 LLVM="{{ llvm_bin }}" defconfig

    {{ config_script }} --enable LTO_CLANG_THIN

    {{ config_script }} --enable KERNEL_ZSTD

    {{ config_script }} --enable EROFS_FS
    {{ config_script }} --enable F2FS_FS

    {{ config_script }} --enable DRM
    {{ config_script }} --enable DRM_VIRTIO_GPU
    {{ config_script }} --enable DRM_VIRTIO_GPU_KMS
    {{ config_script }} --enable DRM_FBDEV_EMULATION
    {{ config_script }} --enable FRAMEBUFFER_CONSOLE
    
    make ARCH=x86_64 LLVM="{{ llvm_bin }}" olddefconfig   

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
    {{ config_script }} --enable ECHO
    {{ config_script }} --enable BLKID
    {{ config_script }} --enable FEATURE_BLKID_TYPE

_configure-dash:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ dash_sources }}"

    autoreconf -fiv
    ./configure --enable-static CFLAGS="-O2"

_configure-limine:
    cd "{{ limine_sources }}" && ./configure --enable-uefi-x86-64
_configure-mesa:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ mesa_sources }}"

    CC=clang CXX=clang++ meson setup build \
        -D platforms=wayland \
        -D glx=disabled \
        -D egl=enabled \
        -D gallium-drivers=virgl \
        -D vulkan-drivers=virtio \
        -D gles1=disabled \
        -D gles2=enabled \
        -D llvm=enabled \
        -D shared-llvm=enabled \
        -D zstd=enabled \
        -D dri3=enabled

build-all: _build-kernel _build-busybox _build-dash _build-limine build-system

_build-kernel:
    cd "{{ kernel_sources }}" && make ARCH=x86_64 LLVM="{{ llvm_bin }}" bzImage -j$(nproc)

_build-busybox:
    cd "{{ busybox_sources }}" && make busybox -j$(nproc)

_build-dash:
    cd "{{ dash_sources }}" && make

_build-limine:
    cd "{{ limine_sources }}" && make

_build-mesa:
    cd "{{ mesa_sources }}" && meson compile -C build

build-system:
    cd system && cargo +stage2 build --release

create-rootfs:
    #!/usr/bin/env bash
    set -euxo pipefail

    # Remove old rootfs if it exists
    rm -rf "{{ rootfs }}"
    rm -rf "{{ work_dir }}"/rootfs.img

    mkdir -p "{{ rootfs }}"

    # Enter rootfs
    cd "{{ rootfs }}"
    
    mkdir dev
    mkdir proc
    mkdir sys
    mkdir tmp
    mkdir disk
    mkdir stem

    cp "{{ system_target }}"/raminit raminit
    # cp "{{ busybox_sources }}"/busybox busybox
    # cp "{{ dash_sources }}"/src/dash sh

    find . | bsdcpio -R root:root -H newc -o | zstd -22 --ultra --long --quiet --stdout >"{{ work_dir }}"/rootfs.img

create-stemfs:
    #!/usr/bin/env bash
    set -euxo pipefail

    # Remove old stemfs if it exists
    rm -rf "{{ stemfs }}"
    mkdir "{{ stemfs }}"

    # Enter rootfs
    cd "{{ stemfs }}"

    # Create basic filesystem
    mkdir dev
    mkdir proc
    mkdir sys
    mkdir tmp
    mkdir disk
    mkdir etc
    
    cp "{{ src }}"/inittab etc/inittab    

    # Copy system manager files
    mkdir system
    cp "{{ system_target }}"/init system/init
    cp "{{ system_target }}"/uname system/uname
    cp "{{ system_target }}"/clear system/clear
    cp "{{ busybox_sources }}"/busybox system/busybox
    cp "{{ dash_sources }}"/src/dash system/sh

    # Strip everything
    # strip --strip-all $ROOTFS/bin/* $ROOTFS/sbin/*
    
create-disk:
    #!/usr/bin/guestfish -f
    echo "Creating image"
    disk-create disk.qcow2 qcow2 10G
    add disk.qcow2
    run

    echo "Partitioning image"
    part_init /dev/sda gpt
    part_add /dev/sda primary 2048 2099199
    part_add /dev/sda primary 2099200 -2048
    part-set-gpt-type /dev/sda 1 C12A7328-F81F-11D2-BA4B-00A0C93EC93B 
    part-set-gpt-type /dev/sda 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709

    echo "Formatting partitions"
    mkfs vfat /dev/sda1
    mkfs f2fs /dev/sda2 features:extra_attr,inode_checksum,sb_checksum

    echo "Mounting efi partition"
    mount /dev/sda1 /
    mkdir /boot
    mkdir-p /EFI/BOOT

    echo "Copying to efi partition"
    copy-in {{ kernel_sources }}/arch/x86/boot/bzImage /boot
    mv /boot/bzImage /boot/kernel.img
    copy-in {{ work_dir }}/rootfs.img /boot
    copy-in {{ limine_sources }}/bin/BOOTX64.EFI /EFI/BOOT
    copy-in limine.cfg /boot

    echo "Unmounting efi partition"
    umount /

    echo "Mounting stem partition"
    mount /dev/sda2 /
    
    # FIXME: figure out how to use globbing here
    echo "Copying to stem partition"
    copy-in {{ work_dir }}/stemfs/dev /
    copy-in {{ work_dir }}/stemfs/disk /
    copy-in {{ work_dir }}/stemfs/etc /
    copy-in {{ work_dir }}/stemfs/proc /
    copy-in {{ work_dir }}/stemfs/sys /
    copy-in {{ work_dir }}/stemfs/system /
    copy-in {{ work_dir }}/stemfs/tmp /

clean:
    rm -rf work
    rm -rf disk
    rm -rf disk.qcow2

    -cd "{{ kernel_sources }}" &&  make mrproper
    -cd "{{ busybox_sources }}" && make mrproper
    -cd "{{ dash_sources }}" && make clean
    -cd "{{ limine_sources}}" && make clean
    
    cd system && cargo clean

    cargo clean

qemu:
    scripts/qemu.sh
