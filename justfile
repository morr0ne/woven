src := `pwd`
kernel_version := "6.7.9"
busybox_version := "1.36.1"
dash_version := "0.5.12"
limine_version := "7.0.5"
mesa_version := "24.0.2"
llvm_version := "18.1.0"
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
system_target := src / "target/x86_64-unknown-linux-none/release"

all: prepare configure build

build: build-all pack

pack: create-rootfs create-stemfs create-iso

prepare:
    woven-sources

configure: _configure-kernel _configure-busybox _configure-dash _configure-limine

_configure-kernel:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ kernel_sources }}"
    
    make ARCH=x86_64 LLVM="{{ llvm_bin }}" defconfig

    {{ config_script }} --disable LTO_CLANG_FULL
    {{ config_script }} --disable LTO_NONE
    {{ config_script }} --enable LTO_CLANG_THIN

    # {{ config_script }} --enable KERNEL_ZSTD

    {{ config_script }} --enable EROFS_FS
    {{ config_script }} --enable EROFS_FS_XATTR
    {{ config_script }} --enable EROFS_FS_POSIX_ACL
    {{ config_script }} --enable EROFS_FS_SECURITY
    {{ config_script }} --enable EROFS_FS_ZIP
    {{ config_script }} --enable EROFS_FS_ZIP_LZMA
    {{ config_script }} --enable EROFS_FS_ZIP_DEFLATE
    {{ config_script }} --enable EROFS_FS_ONDEMAND
    {{ config_script }} --enable EROFS_FS_PCPU_KTHREAD
    {{ config_script }} --enable EROFS_FS_PCPU_KTHREAD_HIPRI
    {{ config_script }} --disable EROFS_FS_DEBUG

    {{ config_script }} --enable DRM
    {{ config_script }} --enable DRM_VIRTIO_GPU
    {{ config_script }} --enable DRM_VIRTIO_GPU_KMS
    {{ config_script }} --enable DRM_FBDEV_EMULATION
    {{ config_script }} --enable DRM_KMS_HELPER
    {{ config_script }} --enable FB_CORE
    {{ config_script }} --enable FB_DEVICE
    {{ config_script }} --enable FRAMEBUFFER_CONSOLE
    {{ config_script }} --disable FRAMEBUFFER_CONSOLE_LEGACY_ACCELERATION
    {{ config_script }} --disable FRAMEBUFFER_CONSOLE_ROTATION
    {{ config_script }} --set-val DRM_FBDEV_OVERALLOC 100
    {{ config_script }} --disable LOGO

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
    {{ config_script }} --enable BLKID
    {{ config_script }} --enable FEATURE_BLKID_TYPE

_configure-dash:
    #!/usr/bin/env bash
    set -euxo pipefail

    cd "{{ dash_sources }}"

    autoreconf -fiv
    ./configure --enable-static CFLAGS="-O2"

_configure-limine:
    cd "{{ limine_sources }}" && ./configure --enable-uefi-x86-64 --enable-bios-cd --enable-uefi-cd --enable-bios
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
    cargo build --release --target x86_64-unknown-linux-none.json

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

    find . | bsdcpio -R root:root -H newc -o | zstd -22 --ultra --long --quiet --stdout >"{{ work_dir }}"/rootfs.img

create-stemfs:
    #!/usr/bin/env bash
    set -euxo pipefail

    # Remove old stemfs if it exists
    rm -rf "{{ stemfs }}"
    rm -rf "{{ work_dir }}"/stemfs.erofs

    # Go into busybox directory
    cd "{{ busybox_sources }}"

    # Create all the symlinks
    make CONFIG_PREFIX="{{ stemfs }}" install

    # Enter rootfs
    cd "{{ stemfs }}"

    # Create basic filesystem
    mkdir dev
    mkdir etc
    mkdir lib
    mkdir proc
    mkdir root
    mkdir sys
    mkdir tmp
    mkdir var
    
    cp "{{ src }}"/inittab etc/inittab

    # Copy shell
    cp "{{ dash_sources }}"/src/dash bin/sh

    # Copy system manager files
    mkdir system
    cp "{{ system_target }}"/init system/init
    cp "{{ system_target }}"/uname system/uname
    cp "{{ system_target }}"/clear system/clear

    # Strip everything
    # strip --strip-all $ROOTFS/bin/* $ROOTFS/sbin/*

    # Pack stemfs
    mkfs.erofs {{ work_dir }}/stemfs.erofs .


create-iso:
    # Remove old isoimage if it exists
    rm -rf "{{ isoimage }}"
    rm -rf woven.iso

    # Create directory for boot files
    mkdir -p "{{ isoimage }}"/boot

    # Copy the actual kernel
    cp "{{ kernel_sources }}"/arch/x86/boot/bzImage "{{ isoimage }}"/boot/kernel.img

    # Copy the initramfs image
    cp "{{ work_dir }}"/rootfs.img "{{ isoimage }}"/boot/rootfs.img
    cp "{{ work_dir }}"/stemfs.erofs "{{ isoimage }}"/stemfs.erofs

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

clean:
    rm -rf work
    rm -rf woven.iso

    cd "{{ kernel_sources }}" &&  make mrproper
    cd "{{ busybox_sources }}" && make mrproper
    cd "{{ dash_sources }}" && make clean
    cd "{{ limine_sources}}" && make clean

    cargo clean

qemu:
    scripts/qemu.sh
