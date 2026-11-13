use crate::read::{Error, Reader, State, be16, be32, range};
use crate::{Dimensions, photoshop, tiff, xmp};
use std::io::{Read, Seek};

const XMP: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
const EXTENDED: &[u8] = b"http://ns.adobe.com/xmp/extension/\0";

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
) -> Result<(), Error> {
    let mut offset = 2;
    let mut fragments = Vec::new();
    while offset < reader.len {
        state.entries(1)?;
        if reader.array::<1>(offset)?[0] != 0xff {
            return Err(Error::Malformed("JPEG marker"));
        }
        offset += 1;
        let mut marker = reader.array::<1>(offset)?[0];
        while marker == 0xff {
            offset += 1;
            marker = reader.array::<1>(offset)?[0];
        }
        offset += 1;
        if matches!(marker, 0xda | 0xd9) {
            break;
        }
        if matches!(marker, 0x01 | 0xd0..=0xd8) {
            continue;
        }
        let size = u64::from(be16(&reader.array::<2>(offset)?));
        if size < 2 {
            return Err(Error::Malformed("JPEG segment length"));
        }
        range(0, reader.len, offset, size)?;
        let start = offset + 2;
        let len = size - 2;
        match marker {
            0xe1 => {
                let header = reader.bytes(start, len.min(35) as usize)?;
                let result = if header.starts_with(b"Exif\0\0") {
                    tiff::read(reader, state, start + 6, len - 6)
                } else if header.starts_with(XMP) {
                    let bytes = reader.bytes(start + XMP.len() as u64, len as usize - XMP.len())?;
                    xmp::read(&bytes, state)
                } else if header.starts_with(EXTENDED) {
                    let bytes = reader
                        .bytes(start + EXTENDED.len() as u64, len as usize - EXTENDED.len())?;
                    if bytes.len() < 40 {
                        Err(Error::Malformed("extended XMP header"))
                    } else {
                        fragments.push(bytes);
                        Ok(())
                    }
                } else {
                    Ok(())
                };
                state.recover(start, result)?;
            }
            0xed => {
                let data = reader.bytes(start, len as usize)?;
                let result = photoshop::read(&data, state);
                state.recover(start, result)?;
            }
            0xc0..=0xc3 | 0xc5..=0xc7 | 0xc9..=0xcb | 0xcd..=0xcf => {
                if len < 6 {
                    return Err(Error::Malformed("JPEG frame"));
                }
                let frame = reader.array::<5>(start)?;
                if state.metadata.dimensions.is_none() {
                    state.metadata.dimensions =
                        Dimensions::new(u32::from(be16(&frame[3..])), u32::from(be16(&frame[1..])));
                }
            }
            _ => {}
        }
        offset += size;
    }
    if !fragments.is_empty() {
        let result = extended_xmp(fragments, state);
        state.recover(offset, result)?;
    }
    Ok(())
}

fn extended_xmp(mut fragments: Vec<Vec<u8>>, state: &mut State) -> Result<(), Error> {
    let Some(id) = state
        .metadata
        .property(xmp::namespace::NOTE, "HasExtendedXMP")
    else {
        return Err(Error::Malformed("unreferenced extended XMP"));
    };
    fragments.retain(|f| f.get(..32) == Some(id.as_bytes()));
    if fragments.is_empty() {
        return Err(Error::Malformed("missing extended XMP"));
    }
    fragments.sort_by_key(|f| be32(&f[36..]));
    let total = be32(&fragments[0][32..]) as usize;
    if total > state.limits.read_bytes {
        return Err(Error::Limit("extended XMP"));
    }
    let mut joined = Vec::new();
    for fragment in fragments {
        if be32(&fragment[32..]) as usize != total
            || be32(&fragment[36..]) as usize != joined.len()
            || fragment.len() - 40 > total - joined.len()
        {
            return Err(Error::Malformed("extended XMP extents"));
        }
        joined.extend_from_slice(&fragment[40..]);
    }
    if joined.len() != total {
        return Err(Error::Malformed("incomplete extended XMP"));
    }
    xmp::read(&joined, state)
}
