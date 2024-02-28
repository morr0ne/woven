#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use core::ffi::CStr;

use rustix::{
    fs::{mkdir, Mode},
    mount::{mount2, mount_move, MountFlags},
    runtime::execve,
};

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}

fn main() -> i32 {
    // unsafe {
    //     execve(
    //         CStr::from_bytes_with_nul_unchecked(b"/bin/sh\0"),
    //         [].as_ptr(),
    //         [].as_ptr(),
    //     );
    // };

    mount2(None, c"/dev", Some(c"devtmpfs"), MountFlags::empty(), None);
    mount2(None, c"/proc", Some(c"proc"), MountFlags::empty(), None);
    mount2(
        None,
        c"/tmp",
        Some(c"tmpfs"),
        MountFlags::empty(),
        Some(c"mode=1777"),
    );
    mount2(None, c"/sys", Some(c"sysfs"), MountFlags::empty(), None);

    mkdir(c"/dev/pts", Mode::empty());

    mount2(
        None,
        c"/dev/pts",
        Some(c"devpts"),
        MountFlags::empty(),
        None,
    );

    // TODO: mount a real fs like squashfs or erofs
    mount2(None, c"/mnt", Some(c"tmpfs"), MountFlags::empty(), None);

    // Critical file system folders
    mkdir(c"/mnt/dev", Mode::empty());
    mkdir(c"/mnt/sys", Mode::empty());
    mkdir(c"/mnt/proc", Mode::empty());
    mkdir(c"/mnt/tmp", Mode::empty());

    mount_move(c"/dev", c"/mnt/dev");
    mount_move(c"/sys", c"/mnt/sys");
    mount_move(c"/proc", c"/mnt/proc");
    mount_move(c"/tmp", c"/mnt/tmp");

    // if let Err(err) = result {
    //     return err.raw_os_error();
    // }

    0
}

#[naked]
#[no_mangle]
unsafe extern "C" fn _start() -> ! {
    use core::arch::asm;

    fn entry() -> ! {
        rustix::runtime::exit_group(main())
    }

    asm!(
        "mov rdi, rsp", // Pass the incoming `rsp` as the arg to `entry`.
        "push rbp",     // Set the return address to zero.
        "jmp {entry}",  // Jump to `entry`.
        entry = sym entry,
        options(noreturn),
    );
}
