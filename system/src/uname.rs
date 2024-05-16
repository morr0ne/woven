#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

extern crate rt;

use rustix::{
    fd::AsFd,
    io::Result,
    stdio::stdout,
    system::{uname, Uname},
};

use rt::io::write_all;

#[no_mangle]
fn main() -> i32 {
    let stdout = unsafe { stdout() };

    if write_uname(uname(), stdout).is_ok() {
        0
    } else {
        1
    }
}

fn write_uname<Fd: AsFd>(uname: Uname, stdout: Fd) -> Result<()> {
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
