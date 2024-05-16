#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use core::arch::asm;

use rustix_dlmalloc::GlobalDlmalloc;

pub mod io;

#[global_allocator]
static DLMALLOC: GlobalDlmalloc = GlobalDlmalloc;

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
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
