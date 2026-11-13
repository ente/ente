use std::io::{self, Write};

use md5::{Digest, Md5};

pub struct Md5Writer<W: Write> {
    inner: W,
    digest: Md5,
}

impl<W: Write> Md5Writer<W> {
    pub fn new(inner: W) -> Self {
        Self {
            inner,
            digest: Md5::new(),
        }
    }

    pub fn finalize(self) -> (W, [u8; 16]) {
        (self.inner, self.digest.finalize().into())
    }
}

impl<W: Write> Write for Md5Writer<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let written = self.inner.write(buf)?;
        self.digest.update(&buf[..written]);
        Ok(written)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_md5_writer_matches_direct_digest() {
        let mut writer = Md5Writer::new(Vec::new());
        writer.write_all(b"hello ").unwrap();
        writer.write_all(b"world").unwrap();
        let (written, md5) = writer.finalize();

        assert_eq!(written, b"hello world");
        assert_eq!(md5, <[u8; 16]>::from(Md5::digest(b"hello world")));
    }
}
