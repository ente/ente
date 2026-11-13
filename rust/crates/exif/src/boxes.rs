use crate::read::{Error, Reader, be32, range};
use std::io::{Read, Seek};

pub(crate) struct BoxRange {
    pub kind: [u8; 4],
    pub start: u64,
    pub len: u64,
}
impl BoxRange {
    pub fn end(&self) -> u64 {
        self.start + self.len
    }
}

pub(crate) fn box_at<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    offset: u64,
    end: u64,
) -> Result<BoxRange, Error> {
    range(0, end, offset, 8)?;
    let header = reader.array::<8>(offset)?;
    let [_, _, _, _, kind @ ..] = header;
    let mut size = u64::from(be32(&header));
    let mut header_size = 8;
    if size == 1 {
        range(0, end, offset, 16)?;
        size = u64::from_be_bytes(reader.array::<8>(offset + 8)?);
        header_size = 16;
    } else if size == 0 {
        size = end - offset;
    }
    if size < header_size {
        return Err(Error::Malformed("box size"));
    }
    range(0, end, offset, size)?;
    Ok(BoxRange {
        kind,
        start: offset + header_size,
        len: size - header_size,
    })
}
