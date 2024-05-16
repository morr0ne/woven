use rustix::{
    fd::AsFd,
    io::{self, Errno, Result},
};

pub fn write_all<Fd: AsFd>(fd: Fd, mut buf: &[u8]) -> Result<()> {
    while !buf.is_empty() {
        match io::write(fd.as_fd(), buf) {
            Ok(n) => buf = &buf[n..],
            Err(Errno::INTR) => {}
            Err(e) => return Err(e),
        }
    }
    Ok(())
}
