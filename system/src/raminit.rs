#![no_std]
#![no_main]
#![allow(internal_features)]
#![feature(lang_items)]
#![feature(core_intrinsics)]
#![feature(naked_functions)]

// TODO: comment everything

extern crate rt;

use core::{ffi::c_char, ptr::null};

use rt::entry;
use rustix::{
    fs::{mkdir, open, stat, Mode, OFlags},
    io::{Errno, Result},
    ioctl::ioctl,
    mount::{mount2, mount_move, mount_none, MountFlags},
    path::Arg,
    process::{chdir, chroot, getpid},
    runtime::execve,
};

mod loop_configure;

use loop_configure::ConfigureLoop;

#[entry]
fn main() -> i32 {
    // Make sure we actually are pid 1 otherwise stuff will go wrong
    if !getpid().is_init() {
        return -1;
    }

    // Mount everything
    // TODO: should allow mounting a specific root
    if let Err(err) = mount_system() {
        return err.raw_os_error();
    }

    // Switch to the real mount
    if let Err(err) = switch_root() {
        return err.raw_os_error();
    }

    0
}

fn switch_root() -> Result<()> {
    chdir(c"/stem")?;

    // TODO: delete everything before mounting

    mount_move(c".", c"/")?;

    chroot(c".")?;
    chdir(c"/")?;

    let argv: &[*const c_char] = &[c"/system/sh".as_ptr(), null()];
    let envp: &[*const c_char] = &[c"PATH=/system".as_ptr(), null()];
    let err = unsafe { execve(c"/system/sh", argv.as_ptr(), envp.as_ptr()) };

    return Err(err);
}

fn mount_system() -> Result<()> {
    mount_none(c"/dev", c"devtmpfs", None)?;
    mount_none(c"/proc", c"proc", None)?;
    mount_none(c"/tmp", c"tmpfs", Some(c"mode=1777"))?;
    mount_none(c"/sys", c"sysfs", None)?;
    mount_none(c"/disk", c"tmpfs", None)?;

    mkdir(c"/dev/pts", Mode::empty())?;

    mount_none(c"/dev/pts", c"devpts", None)?;

    loop {
        match stat(c"/dev/vda2") {
            Ok(_) => break,
            Err(Errno::NOENT) => continue,
            Err(err) => return Err(err),
        }
    }

    mount2(
        Some(c"/dev/vda2"),
        c"/stem",
        Some(c"f2fs"),
        MountFlags::RDONLY,
        None,
    )?;

    mount_move(c"/dev", c"/stem/dev")?;
    mount_move(c"/sys", c"/stem/sys")?;
    mount_move(c"/proc", c"/stem/proc")?;
    mount_move(c"/tmp", c"/stem/tmp")?;
    mount_move(c"/disk", c"/stem/disk")?;

    Ok(())
}

#[allow(unused)]
fn loop_device<P: Arg>(file: P) -> Result<()> {
    let file = open(file, OFlags::RDONLY, Mode::empty())?;

    let loop_device = open(c"/dev/loop0", OFlags::RDWR, Mode::empty())?;

    let configure_loop = ConfigureLoop::new(file);

    // FIXME: handle errors
    let _output = unsafe { ioctl(&loop_device, configure_loop) }?;

    Ok(())
}
