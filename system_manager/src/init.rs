#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]

use origin::{program::*, signal::sig_ign};
use rustix::runtime::fork;
use rustix::{io, process::getpid, stdio::stdout};

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}

#[no_mangle]
extern "C" fn main(_argc: i32, _argv: *const *const u8) -> i32 {
    // Check if we are pid one, otherwise exit with code 1
    if !getpid().is_init() {
        // We don't care if there are any io errors since we are just exiting anyway
        let _ = io::write(unsafe { stdout() }, b"Must be run as PID 1\n");

        // Exit without calling any dtor, we don't have any anyway
        exit_immediately(1)
    }

    // loop {}

    // let f = unsafe { fork() };

    exit_immediately(0)
}
