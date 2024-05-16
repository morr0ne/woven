#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use core::arch::asm;

use rustix::{io::Errno, process::EXIT_SUCCESS};
use rustix_dlmalloc::GlobalDlmalloc;

pub use rt_macros::entry;

pub mod io;

#[global_allocator]
static DLMALLOC: GlobalDlmalloc = GlobalDlmalloc;

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}

pub trait Termination {
    fn exit(self) -> i32;
}

impl Termination for i32 {
    fn exit(self) -> i32 {
        self
    }
}

impl Termination for Errno {
    fn exit(self) -> i32 {
        self.raw_os_error()
    }
}

impl Termination for () {
    fn exit(self) -> i32 {
        EXIT_SUCCESS
    }
}

impl<T, E: Termination> Termination for Result<T, E> {
    fn exit(self) -> i32 {
        match self {
            Ok(_) => EXIT_SUCCESS,
            Err(err) => err.exit(),
        }
    }
}

#[naked]
#[no_mangle]
pub unsafe extern "C" fn _start() -> ! {
    fn entry() -> ! {
        extern "Rust" {
            fn main() -> i32;
        }

        rustix::runtime::exit_group(unsafe { main() })
    }

    asm!(
        "mov rdi, rsp", // Pass the incoming `rsp` as the arg to `entry`.
        "push rbp",     // Set the return address to zero.
        "jmp {entry}",  // Jump to `entry`.
        entry = sym entry,
        options(noreturn),
    );
}
