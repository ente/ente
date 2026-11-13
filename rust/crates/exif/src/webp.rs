use crate::read::{Error, Reader, State, le32, range};
use crate::{Dimensions, tiff, xmp};
use std::io::{Read, Seek};

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
) -> Result<(), Error> {
    let end = u64::from(le32(&reader.array::<4>(4)?)) + 8;
    if end < 12 {
        return Err(Error::Malformed("RIFF size"));
    }
    range(0, reader.len, 0, end)?;
    let mut offset = 12;
    while offset < end {
        state.entries(1)?;
        range(0, end, offset, 8)?;
        let header = reader.array::<8>(offset)?;
        let len = u64::from(le32(&header[4..]));
        range(0, end, offset, 8 + len + (len & 1))?;
        let start = offset + 8;
        let result = match &header[..4] {
            b"EXIF" => {
                let prefix = reader.bytes(start, len.min(6) as usize)?;
                let skip = if prefix == b"Exif\0\0" { 6 } else { 0 };
                tiff::read(reader, state, start + skip, len - skip)
            }
            b"XMP " => xmp::read(&reader.bytes(start, len as usize)?, state),
            b"VP8X" if len >= 10 => {
                let data = reader.array::<10>(start)?;
                let u24 =
                    |b: &[u8]| u32::from(b[0]) | (u32::from(b[1]) << 8) | (u32::from(b[2]) << 16);
                state.metadata.dimensions =
                    Dimensions::new(u24(&data[4..]) + 1, u24(&data[7..]) + 1);
                Ok(())
            }
            b"VP8 " if len >= 10 && state.metadata.dimensions.is_none() => {
                let data = reader.array::<10>(start)?;
                if data[3..6] != [0x9d, 0x01, 0x2a] {
                    return Err(Error::Malformed("VP8 frame"));
                }
                state.metadata.dimensions = Dimensions::new(
                    u32::from(u16::from_le_bytes([data[6], data[7]]) & 0x3fff),
                    u32::from(u16::from_le_bytes([data[8], data[9]]) & 0x3fff),
                );
                Ok(())
            }
            b"VP8L" if len >= 5 && state.metadata.dimensions.is_none() => {
                let data = reader.array::<5>(start)?;
                if data[0] != 0x2f {
                    return Err(Error::Malformed("VP8L frame"));
                }
                let bits = le32(&data[1..]);
                state.metadata.dimensions =
                    Dimensions::new((bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1);
                Ok(())
            }
            _ => Ok(()),
        };
        state.recover(offset, result)?;
        offset += 8 + len + (len & 1);
    }
    Ok(())
}
