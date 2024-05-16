#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

extern crate rt;

use rustix::{
    fd::AsFd,
    io::{self, Errno},
    stdio::stdout,
    system::{uname, Uname},
};

#[no_mangle]
fn main() -> i32 {
    let stdout = unsafe { stdout() };

    if write_uname(uname(), stdout).is_ok() {
        0
    } else {
        1
    }
}

fn write_uname<Fd: AsFd>(uname: Uname, stdout: Fd) -> io::Result<()> {
    let stdout = stdout.as_fd();

    write_all(stdout, uname.sysname().to_bytes())?;
    write_all(stdout, b" ")?;

    write_all(stdout, uname.nodename().to_bytes())?;
    write_all(stdout, b" ")?;

    write_all(stdout, uname.release().to_bytes())?;
    write_all(stdout, b" ")?;

    write_all(stdout, uname.version().to_bytes())?;
    write_all(stdout, b" ")?;

    write_all(stdout, uname.machine().to_bytes())?;
    write_all(stdout, b" ")?;

    write_all(stdout, b"OS")?;
    write_all(stdout, b"\n")?;

    Ok(())
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
