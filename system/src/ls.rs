#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

extern crate rt;

use rustix::{
    fs::{open, Dir, Mode, OFlags},
    io::Result,
    stdio::stdout,
};

use rt::{
    entry,
    io::{write_all, write_str},
};

#[entry]
fn main() -> Result<()> {
    let dir = rt::args().skip(1).next().unwrap_or(c".");

    let stdout = unsafe { stdout() };

    let dir = open(
        dir,
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )?;

    let mut dir = Dir::new(dir)?;

    while let Some(Ok(e)) = dir.next() {
        let name = e.file_name();

        if name == c"." || name == c".." {
            continue;
        }

        write_all(stdout, name.to_bytes())?;
        write_str(stdout, "   ")?;
    }

    write_str(stdout, "\n")?;

    Ok(())
}
