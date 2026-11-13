use crate::boxes::box_at;
use crate::read::{Error, Reader, State, be32, range};
use crate::{Dimensions, Transform, tiff, xmp};
use brotli_decompressor::{BrotliDecompressStream, BrotliResult, BrotliState, StandardAlloc};
use std::io::{Read, Seek};

pub(crate) const SIGNATURE: &[u8] = b"\0\0\0\x0cJXL \r\n\x87\n";

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    bare: bool,
) -> Result<(), Error> {
    let mut prefix = [0; 12];
    if bare {
        let count = reader.len.min(prefix.len() as u64) as usize;
        reader.fill(0, &mut prefix[..count])?;
        return codestream(&prefix[..count], state);
    }
    if reader.array::<20>(12)? != *b"\0\0\0\x14ftypjxl \0\0\0\0jxl " {
        return Err(Error::Malformed("JPEG XL file type"));
    }
    let mut offset = 32;
    let mut count = 0;
    let mut next_part = 0;
    let mut complete = false;
    while offset < reader.len {
        state.entries(1)?;
        let b = box_at(reader, offset, reader.len)?;
        let start = b.start;
        let len = b.len;
        let kind = &b.kind;
        let result = match kind {
            b"jxlc" | b"jxlp" => {
                if complete || (kind == b"jxlc" && next_part != 0) {
                    return Err(Error::Malformed("JPEG XL codestream sequence"));
                }
                let skip = if kind == b"jxlp" {
                    let index = be32(&reader.array::<4>(range(start, len, 0, 4)?)?);
                    if index & 0x7fff_ffff != next_part {
                        return Err(Error::Malformed("JPEG XL part index"));
                    }
                    next_part += 1;
                    complete = index & 0x8000_0000 != 0;
                    4
                } else {
                    complete = true;
                    0
                };
                let take = (len - skip).min((prefix.len() - count) as u64) as usize;
                if take != 0 {
                    reader.fill(start + skip, &mut prefix[count..count + take])?;
                    count += take;
                }
                Ok(())
            }
            b"Exif" => tiff::exif_block(reader, state, start, len),
            b"xml " => xmp::read(&reader.bytes(start, length(len)?)?, state),
            b"brob" => compressed(reader, state, start, len),
            b"JXL " | b"ftyp" => Err(Error::Malformed("duplicate JPEG XL header")),
            _ => Ok(()),
        };
        state.recover(offset, result)?;
        offset = b.end();
    }
    if !complete {
        return Err(Error::Malformed("incomplete JPEG XL codestream"));
    }
    codestream(&prefix[..count], state)
}

fn codestream(bytes: &[u8], state: &mut State) -> Result<(), Error> {
    let mut bits = Bits { bytes, position: 0 };
    if bits.take(16)? != 0x0aff {
        return Err(Error::Malformed("JPEG XL signature"));
    }
    let div8 = bits.take(1)? != 0;
    let height = bits.dimension(div8)?;
    let ratio = bits.take(3)?;
    let width = if ratio == 0 {
        bits.dimension(div8)?
    } else {
        let (numerator, denominator) =
            [(1, 1), (6, 5), (4, 3), (3, 2), (16, 9), (5, 4), (2, 1)][(ratio - 1) as usize];
        (u64::from(height) * numerator / denominator) as u32
    };
    let all_default = bits.take(1)? != 0;
    let orientation = if !all_default && bits.take(1)? != 0 {
        bits.take(3)? as u8 + 1
    } else {
        1
    };
    state.retain(std::mem::size_of::<Transform>())?;
    state.metadata.dimensions = Dimensions::new(width, height);
    state
        .metadata
        .transforms
        .push(Transform::Orientation(orientation));
    Ok(())
}

fn compressed<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    start: u64,
    len: u64,
) -> Result<(), Error> {
    let kind = reader.array::<4>(range(start, len, 0, 4)?)?;
    if &kind == b"brob" || kind.starts_with(b"jxl") {
        return Err(Error::Malformed("JPEG XL compressed box type"));
    }
    if !matches!(&kind, b"Exif" | b"xml ") {
        return Ok(());
    }
    let input = reader.bytes(start + 4, length(len - 4)?)?;
    let bytes = decompress(&input, state)?;
    if &kind == b"Exif" {
        let mut source = std::io::Cursor::new(&bytes);
        let mut buffer = Reader::new(&mut source, state.limits)?;
        tiff::exif_block(&mut buffer, state, 0, bytes.len() as u64)
    } else {
        xmp::read(&bytes, state)
    }
}

fn decompress(input: &[u8], state: &mut State) -> Result<Vec<u8>, Error> {
    let first = *input.first().ok_or(Error::Malformed("Brotli header"))?;
    let window_bits = if first & 1 == 0 {
        16
    } else if first & 0x0f != 1 {
        17 + ((first >> 1) & 7)
    } else {
        match (first >> 4) & 7 {
            0 => 17,
            1 => return Err(Error::Malformed("Brotli window")),
            value => 8 + value,
        }
    };
    if (1u64 << window_bits) > state.limits.read_bytes as u64 {
        return Err(Error::Limit("Brotli window"));
    }
    let limit = state.expansion_limit();
    let mut output = vec![0; limit.min(4096)];
    let mut decoder = BrotliState::new_strict(
        StandardAlloc::default(),
        StandardAlloc::default(),
        StandardAlloc::default(),
    );
    let mut available_in = input.len();
    let mut input_offset = 0;
    let mut output_offset = 0;
    let mut total = 0;
    loop {
        let before = output_offset;
        let mut available_out = output.len() - output_offset;
        let result = BrotliDecompressStream(
            &mut available_in,
            &mut input_offset,
            input,
            &mut available_out,
            &mut output_offset,
            &mut output,
            &mut total,
            &mut decoder,
        );
        state.expanded(output_offset - before)?;
        match result {
            BrotliResult::ResultSuccess if input_offset == input.len() => {
                output.truncate(output_offset);
                return Ok(output);
            }
            BrotliResult::NeedsMoreOutput => {
                if output.len() == limit {
                    return Err(Error::Limit("Brotli output"));
                }
                output.resize(output.len().saturating_mul(2).min(limit), 0);
            }
            _ => return Err(Error::Malformed("Brotli stream")),
        }
    }
}

fn length(value: u64) -> Result<usize, Error> {
    usize::try_from(value).map_err(|_| Error::Limit("JPEG XL box bytes"))
}

struct Bits<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl Bits<'_> {
    fn take(&mut self, count: usize) -> Result<u32, Error> {
        let mut value = 0;
        for shift in 0..count {
            let byte = self
                .bytes
                .get(self.position / 8)
                .ok_or(Error::Malformed("JPEG XL header"))?;
            value |= u32::from((byte >> (self.position % 8)) & 1) << shift;
            self.position += 1;
        }
        Ok(value)
    }

    fn dimension(&mut self, div8: bool) -> Result<u32, Error> {
        if div8 {
            Ok(8 * (1 + self.take(5)?))
        } else {
            let count = [9, 13, 18, 30][self.take(2)? as usize];
            Ok(1 + self.take(count)?)
        }
    }
}
