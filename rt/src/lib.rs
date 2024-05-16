#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use core::{
    arch::asm,
    ffi::{c_int, c_uint, CStr},
    ptr::null_mut,
    sync::atomic::{AtomicI32, AtomicPtr, Ordering},
};

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

impl<T: Termination, E: Termination> Termination for Result<T, E> {
    fn exit(self) -> i32 {
        match self {
            Ok(value) => value.exit(),
            Err(err) => err.exit(),
        }
    }
}

static ARGC: AtomicI32 = AtomicI32::new(0);
static ARGV: AtomicPtr<*const u8> = AtomicPtr::new(null_mut());
static ENVP: AtomicPtr<*const u8> = AtomicPtr::new(null_mut());

#[naked]
#[no_mangle]
pub unsafe extern "C" fn _start() -> ! {
    fn entry(mem: *mut usize) -> ! {
        extern "Rust" {
            fn main() -> i32;
        }

        unsafe {
            let kernel_argc = *mem;
            let argc = kernel_argc as c_int;
            let argv = mem.add(1).cast::<*mut u8>();
            let envp = argv.add(argc as c_uint as usize + 1);

            ARGC.store(argc, Ordering::Relaxed);
            ARGV.store(argv as *mut _, Ordering::Relaxed);
            ENVP.store(envp as *mut _, Ordering::Relaxed);
        };

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

pub fn args() -> Args {
    Args { index: 0 }
}

pub struct Args {
    index: usize,
}

impl Iterator for Args {
    type Item = &'static CStr;

    fn next(&mut self) -> Option<Self::Item> {
        let argv = ARGV.load(Ordering::Relaxed);
        let argc = ARGC.load(Ordering::Relaxed);

        if self.index < argc as usize {
            unsafe {
                let arg = argv.add(self.index);
                self.index += 1;

                Some(CStr::from_ptr(arg.read().cast()))
            }
        } else {
            None
        }
    }
}

impl ExactSizeIterator for Args {
    fn len(&self) -> usize {
        let argc = ARGC.load(Ordering::Relaxed);

        argc as usize - self.index
    }
}
