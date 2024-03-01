#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use rustix::{
    fd::AsFd,
    io::{self, Errno},
    stdio::stdout,
};

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}

/*
FIXME

The current implementation simply writes e couple of ansi escape codes to stdout.
Is that right? It does work but it doesn't feel like it's the correct solution.
Perhaps it is and other programs are just overengineered, or perhaps I'm just stupid. Who can say? Maybe its both.
*/
fn main() -> i32 {
    let stdout = unsafe { stdout() };

    if write_all(stdout, b"\x1B[H\x1B[2J").is_ok() {
        0
    } else {
        1
    }
}

fn write_all<Fd: AsFd>(fd: Fd, mut buf: &[u8]) -> io::Result<()> {
    while !buf.is_empty() {
        match io::write(fd.as_fd(), buf) {
            Ok(n) => buf = &buf[n..],
            Err(Errno::INTR) => {}
            Err(e) => return Err(e),
        }
    }
    Ok(())
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
