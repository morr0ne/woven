#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use core::ffi::CStr;

use rustix::{
    fs::{mkdir, Mode},
    io,
    mount::{mount2, mount_move, mount_none, MountFlags},
    process::{getpid, waitpid, WaitOptions},
    runtime::{execve, fork, Fork},
    stdio::stdout,
    thread::{nanosleep, Timespec},
};

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}

fn main() -> i32 {
    mount_none(c"/dev", c"devtmpfs", None);
    mount_none(c"/proc", c"proc", None);
    mount_none(c"/tmp", c"tmpfs", Some(c"mode=1777"));
    mount_none(c"/sys", c"sysfs", None);

    mkdir(c"/dev/pts", Mode::empty());

    mount_none(c"/dev/pts", c"devpts", None);

    // TODO: mount a real fs like squashfs or erofs
    mount_none(c"/mnt", c"tmpfs", None);

    // Critical file system folders
    mkdir(c"/mnt/dev", Mode::empty());
    mkdir(c"/mnt/sys", Mode::empty());
    mkdir(c"/mnt/proc", Mode::empty());
    mkdir(c"/mnt/tmp", Mode::empty());

    mount_move(c"/dev", c"/mnt/dev");
    mount_move(c"/sys", c"/mnt/sys");
    mount_move(c"/proc", c"/mnt/proc");
    mount_move(c"/tmp", c"/mnt/tmp");

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
