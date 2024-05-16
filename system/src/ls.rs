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

use rt::{entry, io::write_all};

#[entry]
fn main() -> Result<()> {
    let stdout = unsafe { stdout() };

    let dir = open(
        c".",
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )?;

    let mut dir = Dir::new(dir)?;

    while let Some(Ok(e)) = dir.next() {
        let name = e.file_name();

        if name == c"." || name == c".." {
            continue;
        }

        write_all(stdout, name.to_bytes_with_nul())?;
        write_all(stdout, c"   ".to_bytes_with_nul())?;
    }

    write_all(stdout, c"\n".to_bytes_with_nul())?;

    Ok(())
}
