#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use core::ffi::CStr;

use rustix::{
    io,
    process::getpid,
    runtime::execve,
    stdio::stdout,
    thread::{nanosleep, Timespec},
};

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}

fn main() -> i32 {
    // Check if we are pid one, otherwise exit with code 1
    if !getpid().is_init() {
        // We don't care if there are any io errors since we are just exiting anyway
        let _ = io::write(unsafe { stdout() }, b"Must be run as PID 1\n");

        return 1;
    }

    unsafe {
        execve(
            CStr::from_bytes_with_nul_unchecked(b"/bin/sh\0"),
            [].as_ptr(),
            [].as_ptr(),
        );
    };

    0

    // let pid = unsafe { fork() };

    // if let Ok(None) = pid {
    //     unsafe {
    //         execve(
    //             CStr::from_bytes_with_nul_unchecked(b"/bin/sh\0"),
    //             [].as_ptr(),
    //             [].as_ptr(),
    //         );
    //     }
    // }

    // loop {
    //     sleep()
    // }
}

#[allow(unused)]
fn sleep() {
    let timespec = Timespec {
        tv_sec: 1,
        tv_nsec: 0,
    };

    let _ = nanosleep(&timespec);
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
