src := `pwd`
kernel_version := `cargo run --quiet --release --bin woven-sources -- linux`
busybox_version := `cargo run --quiet --release --bin woven-sources -- busybox`
dash_version := `cargo run --quiet --release --bin woven-sources -- dash`
limine_version := `cargo run --quiet --release --bin woven-sources -- limine`
mesa_version := `cargo run --quiet --release --bin woven-sources -- mesa`
llvm_version := `cargo run --quiet --release --bin woven-sources -- llvm`
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

all: prepare configure build

build: build-all pack

pack: create-rootfs create-stemfs create-disk

prepare:
    cargo run --release --bin woven-sources
    
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

    meson setup build \
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
    cd system && cargo build --release --target x86_64-unknown-linux-none.json

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
    mkdir -p disk/efi
    mkdir -p disk/stem

    # remove old disk if it exists
    rm -rf disk.qcow2

    qemu-img create -f qcow2 disk.qcow2 10G
    sudo qemu-nbd --connect /dev/nbd0 disk.qcow2

    sudo parted --script /dev/nbd0 mklabel gpt 
    sudo parted --script /dev/nbd0 mkpart "BOOT" fat32 1MiB 301MiB 
    sudo parted --script /dev/nbd0 mkpart "ROOT" f2fs 301MiB 100%

    sudo mkfs.fat -F32 /dev/nbd0p1
    sudo mkfs.f2fs -f -l ROOT -O extra_attr,inode_checksum,sb_checksum /dev/nbd0p2
    sudo mount /dev/nbd0p1 disk/efi -o uid=$UID,gid=$(id -g)
    sudo mount /dev/nbd0p2 disk/stem

    sudo chown -R fede:fede disk/stem

    # Create directory for boot files
    mkdir -p disk/efi/boot

    # Copy the actual kernel
    cp "{{ kernel_sources }}"/arch/x86/boot/bzImage disk/efi/boot/kernel.img

    # Copy the initramfs image
    cp "{{ work_dir }}"/rootfs.img disk/efi/boot/rootfs.img
    cp -r "{{ work_dir }}"/stemfs/* disk/stem

    # Copy limine config
    cp limine.cfg disk/efi/boot

    mkdir -p disk/efi/EFI/BOOT
    cp "{{ limine_sources }}"/bin/BOOTX64.EFI disk/efi/EFI/BOOT

    sudo umount -R disk/efi
    sudo umount -R disk/stem
    sudo qemu-nbd --disconnect /dev/nbd0

create-usb:
    mkdir -p disk/efi
    mkdir -p disk/stem

    sudo parted --script /dev/sda mklabel gpt 
    sudo parted --script /dev/sda mkpart "BOOT" fat32 1MiB 301MiB 
    sudo parted --script /dev/sda mkpart "ROOT" f2fs 301MiB 100%

    sudo mkfs.fat -F32 /dev/sda1
    sudo mkfs.f2fs -f -l ROOT -O extra_attr,inode_checksum,sb_checksum /dev/sda2
    sudo mount /dev/sda1 disk/efi -o uid=$UID,gid=$(id -g)
    sudo mount /dev/sda2 disk/stem

    sudo chown -R fede:fede disk/stem

    # Create directory for boot files
    mkdir -p disk/efi/boot

    # Copy the actual kernel
    cp "{{ kernel_sources }}"/arch/x86/boot/bzImage disk/efi/boot/kernel.img

    # Copy the initramfs image
    cp "{{ work_dir }}"/rootfs.img disk/efi/boot/rootfs.img
    cp -r "{{ work_dir }}"/stemfs/* disk/stem

    # Copy limine config
    cp limine.cfg disk/efi/boot

    mkdir -p disk/efi/EFI/BOOT
    cp "{{ limine_sources }}"/bin/BOOTX64.EFI disk/efi/EFI/BOOT

    sudo umount -R disk/efi
    sudo umount -R disk/stem

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
