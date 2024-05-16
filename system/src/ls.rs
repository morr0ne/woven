#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

use rustix::{
    fd::AsFd,
    fs::{open, Dir, Mode, OFlags},
    io::{self, Errno, Result},
    stdio::stdout,
};

use rustix_dlmalloc::GlobalDlmalloc;

#[global_allocator]
static Dlmalloc: GlobalDlmalloc = GlobalDlmalloc;

fn main() -> i32 {
    if let Err(err) = run() {
        return err.raw_os_error();
    }

    0
}

fn run() -> Result<()> {
    let stdout = unsafe { stdout() };

    let dir = open(
        c".",
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )?;

    let mut dir = Dir::new(dir)?;

    while let Some(Ok(e)) = dir.next() {
        let name = e.file_name();
        write_all(stdout, name.to_bytes_with_nul())?;
        write_all(stdout, c" ".to_bytes_with_nul())?;
    }

    write_all(stdout, c"\n".to_bytes_with_nul())?;

    Ok(())
}

fn write_all<Fd: AsFd>(fd: Fd, mut buf: &[u8]) -> Result<()> {
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

#[panic_handler]
fn panic(_panic: &core::panic::PanicInfo<'_>) -> ! {
    core::intrinsics::abort()
}
