use crate::Mode;
use crate::read::{Error, Reader, State, be32, range};
use crate::tags::{self, Ifd, Rational, Tag, Value};
use std::io::{Read, Seek};

pub(crate) fn read_bytes(bytes: &[u8], state: &mut State) -> Result<(), Error> {
    let mut source = std::io::Cursor::new(bytes);
    let mut reader = Reader::new(&mut source, state.limits)?;
    read(&mut reader, state, 0, bytes.len() as u64)
}

pub(crate) fn exif_block<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    start: u64,
    len: u64,
) -> Result<(), Error> {
    let offset = u64::from(be32(&reader.array::<4>(range(start, len, 0, 4)?)?)) + 4;
    let base = range(start, len, offset, 8)?;
    read(reader, state, base, len - offset)
}

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    base: u64,
    len: u64,
) -> Result<(), Error> {
    let header = reader.array::<8>(range(base, len, 0, 8)?)?;
    let endian = match &header[..2] {
        b"II" => Endian::Little,
        b"MM" => Endian::Big,
        _ => return Err(Error::Malformed("TIFF byte order")),
    };
    match endian.u16(&header[2..]) {
        42 => {}
        43 => return Err(Error::Unsupported("BigTIFF")),
        _ => return Err(Error::Malformed("TIFF magic")),
    }
    let mut tiff = Tiff {
        base,
        len,
        endian,
        pending: vec![(u64::from(endian.u32(&header[4..])), Ifd::Image(0), 0)],
        seen: Vec::new(),
        image_index: 0,
    };
    while let Some((offset, ifd, depth)) = tiff.pending.pop() {
        if offset == 0 {
            continue;
        }
        if tiff.seen.contains(&offset) {
            return Err(Error::Malformed("cyclic IFD"));
        }
        if tiff.seen.len() >= state.limits.directories {
            return Err(Error::Limit("directories"));
        }
        if depth >= state.limits.depth {
            return Err(Error::Limit("IFD depth"));
        }
        tiff.seen.push(offset);
        let result = tiff.read_ifd(reader, state, offset, ifd, depth);
        state.recover(base, result)?;
    }
    Ok(())
}

struct Tiff {
    base: u64,
    len: u64,
    endian: Endian,
    pending: Vec<(u64, Ifd, usize)>,
    seen: Vec<u64>,
    image_index: u16,
}

impl Tiff {
    fn read_ifd<R: Read + Seek>(
        &mut self,
        reader: &mut Reader<'_, R>,
        state: &mut State,
        offset: u64,
        ifd: Ifd,
        depth: usize,
    ) -> Result<(), Error> {
        let count = usize::from(
            self.endian
                .u16(&reader.array::<2>(range(self.base, self.len, offset, 2)?)?),
        );
        state.entries(count)?;
        let table_size = count * 12 + 4;
        let table = reader.bytes(
            range(self.base, self.len, offset + 2, table_size as u64)?,
            table_size,
        )?;
        for entry in table[..count * 12].as_chunks::<12>().0 {
            let id = self.endian.u16(entry);
            let field_type = self.endian.u16(&entry[2..]);
            let count = self.endian.u32(&entry[4..]);
            let width = match field_type {
                1 | 2 | 6 | 7 => 1,
                3 | 8 => 2,
                4 | 9 | 11 | 13 => 4,
                5 | 10 | 12 => 8,
                _ => {
                    state.recover(
                        self.base + offset,
                        Err(Error::Unsupported("TIFF field type")),
                    )?;
                    continue;
                }
            };
            let bytes = u64::from(count) * width;
            let pointer = matches!(id, 0x8769 | 0x8825 | 0xa005 | 0x14a);
            let embedded = matches!(id, 0x2bc | 0x83bb | 0x8649);
            if !pointer && !embedded && state.mode == Mode::Summary && !tags::selected(ifd, id) {
                continue;
            }
            let omitted = !pointer
                && !embedded
                && (id == 0x927c
                    || tags::name(ifd, id).is_none()
                    || matches!(id, 0x111 | 0x117 | 0x144 | 0x145 | 0x201 | 0x202));
            if omitted {
                state.retain(std::mem::size_of::<Tag>())?;
                state.metadata.tags.push(Tag {
                    ifd,
                    id,
                    field_type,
                    count,
                    value: Value::Omitted { bytes },
                });
                continue;
            }
            if bytes > state.limits.value_bytes as u64 && !embedded {
                return Err(Error::Limit("tag value"));
            }
            let location = if bytes <= 4 {
                None
            } else {
                Some(u64::from(self.endian.u32(&entry[8..])))
            };
            let data = match location {
                None => entry[8..8 + bytes as usize].to_vec(),
                Some(position) => {
                    let position = match range(self.base, self.len, position, bytes) {
                        Ok(p) => p,
                        Err(e) => {
                            state.recover(self.base + offset, Err(e))?;
                            continue;
                        }
                    };
                    reader.bytes(
                        position,
                        usize::try_from(bytes).map_err(|_| Error::Limit("tag value"))?,
                    )?
                }
            };
            if embedded {
                let result = match id {
                    0x2bc => crate::xmp::read(&data, state),
                    0x83bb => crate::iptc::read(&data, state),
                    _ => crate::photoshop::read(&data, state),
                };
                state.recover(location.unwrap_or(offset) + self.base, result)?;
                continue;
            }
            if pointer {
                if !matches!(field_type, 4 | 13) {
                    state.recover(
                        self.base + offset,
                        Err(Error::Malformed("IFD pointer type")),
                    )?;
                    continue;
                }
                for bytes in data.as_chunks::<4>().0 {
                    if self.pending.len() + self.seen.len() >= state.limits.directories {
                        return Err(Error::Limit("directories"));
                    }
                    let child = match id {
                        0x8769 => Ifd::Exif(ifd.image()),
                        0x8825 => Ifd::Gps(ifd.image()),
                        0xa005 => Ifd::Interop(ifd.image()),
                        _ => {
                            self.image_index = self
                                .image_index
                                .checked_add(1)
                                .ok_or(Error::Limit("image indices"))?;
                            Ifd::Image(self.image_index)
                        }
                    };
                    if state.mode == Mode::Details || child.image() == 0 {
                        self.pending
                            .push((u64::from(self.endian.u32(bytes)), child, depth + 1));
                    }
                }
                continue;
            }
            state.retain(std::mem::size_of::<Tag>() + data.len() * 4)?;
            state.metadata.tags.push(Tag {
                ifd,
                id,
                field_type,
                count,
                value: decode(self.endian, field_type, data),
            });
        }
        let next = self.endian.u32(&table[count * 12..]);
        if next != 0 && state.mode == Mode::Details {
            self.image_index = self
                .image_index
                .checked_add(1)
                .ok_or(Error::Limit("image indices"))?;
            self.pending
                .push((u64::from(next), Ifd::Image(self.image_index), depth + 1));
        }
        Ok(())
    }
}

fn decode(endian: Endian, field_type: u16, data: Vec<u8>) -> Value {
    match field_type {
        1 => Value::Unsigned(data.into_iter().map(u32::from).collect()),
        2 => Value::Ascii(data),
        3 => Value::Unsigned(
            data.as_chunks::<2>()
                .0
                .iter()
                .map(|b| u32::from(endian.u16(b)))
                .collect(),
        ),
        4 | 13 => Value::Unsigned(
            data.as_chunks::<4>()
                .0
                .iter()
                .map(|b| endian.u32(b))
                .collect(),
        ),
        5 | 10 => Value::Rational(
            data.as_chunks::<8>()
                .0
                .iter()
                .map(|b| {
                    let number = |b| {
                        if field_type == 10 {
                            i64::from(endian.u32(b) as i32)
                        } else {
                            i64::from(endian.u32(b))
                        }
                    };
                    Rational {
                        numerator: number(b),
                        denominator: number(&b[4..]),
                    }
                })
                .collect(),
        ),
        6 => Value::Signed(data.into_iter().map(|b| i32::from(b as i8)).collect()),
        8 => Value::Signed(
            data.as_chunks::<2>()
                .0
                .iter()
                .map(|b| i32::from(endian.u16(b) as i16))
                .collect(),
        ),
        9 => Value::Signed(
            data.as_chunks::<4>()
                .0
                .iter()
                .map(|b| endian.u32(b) as i32)
                .collect(),
        ),
        11 => Value::Float(
            data.as_chunks::<4>()
                .0
                .iter()
                .map(|b| f64::from(f32::from_bits(endian.u32(b))))
                .collect(),
        ),
        12 => Value::Float(
            data.as_chunks::<8>()
                .0
                .iter()
                .map(|b| {
                    let a = endian.u32(b) as u64;
                    let z = endian.u32(&b[4..]) as u64;
                    f64::from_bits(match endian {
                        Endian::Little => a | (z << 32),
                        Endian::Big => (a << 32) | z,
                    })
                })
                .collect(),
        ),
        _ => Value::Bytes(data),
    }
}

#[derive(Clone, Copy)]
enum Endian {
    Little,
    Big,
}
impl Endian {
    fn u16(self, b: &[u8]) -> u16 {
        match self {
            Self::Little => u16::from_le_bytes([b[0], b[1]]),
            Self::Big => u16::from_be_bytes([b[0], b[1]]),
        }
    }
    fn u32(self, b: &[u8]) -> u32 {
        match self {
            Self::Little => u32::from_le_bytes([b[0], b[1], b[2], b[3]]),
            Self::Big => u32::from_be_bytes([b[0], b[1], b[2], b[3]]),
        }
    }
}
