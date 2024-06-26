#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

extern crate rt;

use rustix::{io::Result, stdio::stdout};

use rt::{entry, io::write_all};

/*
FIXME

The current implementation simply writes e couple of ansi escape codes to stdout.
Is that right? It does work but it doesn't feel like it's the correct solution.
Perhaps it is and other programs are just overengineered, or perhaps I'm just stupid. Who can say? Maybe its both.
*/
#[entry]
fn main() -> Result<()> {
    let stdout = unsafe { stdout() };

    write_all(stdout, b"\x1B[H\x1B[2J")?;

    Ok(())
}
