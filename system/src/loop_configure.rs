use core::{
    ffi::{c_int, c_uint, c_void},
    ptr::{self, null_mut},
};
use linux_raw_sys::loop_device::{loop_config, loop_info64, LOOP_CONFIGURE, LOOP_CTL_GET_FREE};
use rustix::{
    fd::IntoRawFd,
    io::Result,
    ioctl::{Ioctl, IoctlOutput, Opcode},
};

pub struct FreeLoop;

unsafe impl Ioctl for FreeLoop {
    type Output = c_int;

    const OPCODE: Opcode = Opcode::old(LOOP_CTL_GET_FREE);

    const IS_MUTATING: bool = true;

    fn as_ptr(&mut self) -> *mut c_void {
        null_mut()
    }

    unsafe fn output_from_ptr(
        out: IoctlOutput,
        _extract_output: *mut c_void,
    ) -> Result<Self::Output> {
        Ok(out)
    }
}

#[repr(transparent)]
pub struct ConfigureLoop {
    config: loop_config,
}

unsafe impl Ioctl for ConfigureLoop {
    type Output = c_int;

    const OPCODE: Opcode = Opcode::old(LOOP_CONFIGURE);

    const IS_MUTATING: bool = true;

    fn as_ptr(&mut self) -> *mut c_void {
        ptr::addr_of_mut!(self.config).cast()
    }

    unsafe fn output_from_ptr(
        out: IoctlOutput,
        _extract_output: *mut c_void,
    ) -> Result<Self::Output> {
        Ok(out)
    }
}

impl ConfigureLoop {
    pub fn new<Fd: IntoRawFd>(fd: Fd) -> Self {
        let config = loop_config {
            fd: fd.into_raw_fd() as c_uint,
            block_size: 0,
            info: loop_info64 {
                lo_device: 0,
                lo_inode: 0,
                lo_rdevice: 0,
                lo_offset: 0,
                lo_sizelimit: 0,
                lo_number: 0,
                lo_encrypt_type: 0,
                lo_encrypt_key_size: 0,
                lo_flags: 0,
                lo_file_name: [0; 64],
                lo_crypt_name: [0; 64],
                lo_encrypt_key: [0; 32],
                lo_init: [0; 2],
            },
            __reserved: [0; 8],
        };

        Self { config }
    }
}
