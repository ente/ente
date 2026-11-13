use crate::read::{Error, Reader, State, range};
use crate::{Dimensions, xmp};
use std::io::{Read, Seek};

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
) -> Result<(), Error> {
    let data = reader.array::<7>(6)?;
    state.metadata.dimensions = Dimensions::new(
        u32::from(u16::from_le_bytes([data[0], data[1]])),
        u32::from(u16::from_le_bytes([data[2], data[3]])),
    );
    let table_size = |flags: u8| {
        if flags & 0x80 != 0 {
            3u64 << ((flags & 7) + 1)
        } else {
            0
        }
    };
    let mut offset = 13 + table_size(data[4]);
    while offset < reader.len {
        state.entries(1)?;
        let marker = reader.array::<1>(offset)?[0];
        offset += 1;
        match marker {
            0x3b => return Ok(()),
            0x2c => {
                let image = reader.array::<9>(offset)?;
                offset += 10 + table_size(image[8]);
                skip_subblocks(reader, state, &mut offset)?;
            }
            0x21 => {
                let label = reader.array::<1>(offset)?[0];
                offset += 1;
                if label == 0xff {
                    let size = reader.array::<1>(offset)?[0] as usize;
                    offset += 1;
                    let app = reader.bytes(offset, size)?;
                    offset += size as u64;
                    if app == b"XMP DataXMP" {
                        let start = offset;
                        let mut packet = Vec::new();
                        loop {
                            let scan = packet.len().saturating_sub(257);
                            let count = (reader.len - offset).min(4096) as usize;
                            if count == 0 {
                                return Err(Error::Malformed("GIF XMP trailer"));
                            }
                            packet.extend(reader.bytes(offset, count)?);
                            offset += count as u64;
                            if let Some(end) = packet[scan..].windows(258).position(|w| {
                                w[0] == 1
                                    && w[257] == 0
                                    && w[1..257].iter().copied().eq((0..=255).rev())
                            }) {
                                let end = scan + end;
                                offset = start + end as u64 + 258;
                                packet.truncate(end);
                                let result = xmp::read(&packet, state);
                                state.recover(offset, result)?;
                                break;
                            }
                        }
                    } else {
                        skip_subblocks(reader, state, &mut offset)?;
                    }
                } else {
                    skip_subblocks(reader, state, &mut offset)?;
                }
            }
            _ => return Err(Error::Malformed("GIF block")),
        }
    }
    Err(Error::Malformed("missing GIF trailer"))
}

fn skip_subblocks<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    offset: &mut u64,
) -> Result<(), Error> {
    loop {
        state.entries(1)?;
        let size = u64::from(reader.array::<1>(*offset)?[0]);
        range(0, reader.len, *offset, size + 1)?;
        *offset += size + 1;
        if size == 0 {
            return Ok(());
        }
    }
}
