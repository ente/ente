use crate::read::{Cursor, Error, Reader, State, be32, range};
use crate::{Dimensions, Mode, iptc, photoshop, tiff, xmp};
use std::borrow::Cow;
use std::io::{Read, Seek};

const MAX_KEYWORD_LEN: usize = 79;

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
) -> Result<(), Error> {
    let mut offset = 8;
    while offset < reader.len {
        state.entries(1)?;
        let header = reader.array::<8>(offset)?;
        let len = u64::from(be32(&header));
        range(0, reader.len, offset, len + 12)?;
        let start = offset + 8;
        let result = match &header[4..] {
            b"IHDR" => {
                if offset != 8 || len != 13 {
                    return Err(Error::Malformed("PNG IHDR"));
                }
                let data = reader.array::<8>(start)?;
                state.metadata.dimensions = Dimensions::new(be32(&data), be32(&data[4..]));
                Ok(())
            }
            b"eXIf" => tiff::read(reader, state, start, len),
            b"iTXt" | b"zTXt" | b"tEXt" => text(reader, start, len as usize, &header[4..], state),
            b"IEND" => {
                if len != 0 || state.metadata.dimensions.is_none() {
                    return Err(Error::Malformed("PNG IEND"));
                }
                return Ok(());
            }
            _ => Ok(()),
        };
        state.recover(offset, result)?;
        offset += len + 12;
    }
    Err(Error::Malformed("missing PNG IEND"))
}

fn text<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    start: u64,
    len: usize,
    kind: &[u8],
    state: &mut State,
) -> Result<(), Error> {
    let mut header = [0; MAX_KEYWORD_LEN + 1];
    let header = &mut header[..len.min(MAX_KEYWORD_LEN + 1)];
    reader.fill(start, header)?;
    let mut cursor = Cursor::new(header);
    let key = cursor.terminated_bytes()?;
    if !(1..=MAX_KEYWORD_LEN).contains(&key.len()) {
        return Err(Error::Malformed("PNG keyword"));
    }
    let is_profile = matches!(
        key,
        b"Raw profile type exif"
            | b"Raw profile type APP1"
            | b"Raw profile type iptc"
            | b"Raw profile type 8bim"
            | b"Raw profile type xmp"
    );
    if key != b"XML:com.adobe.xmp" && !is_profile && state.mode == Mode::Summary {
        return Ok(());
    }
    let prefix = &header[cursor.pos..];
    let data = if len == header.len() {
        Cow::Borrowed(prefix)
    } else {
        let remaining = len - header.len();
        let offset = start + header.len() as u64;
        reader.check(offset, remaining)?;
        let mut data = vec![0; prefix.len() + remaining];
        data[..prefix.len()].copy_from_slice(prefix);
        reader.fill(offset, &mut data[prefix.len()..])?;
        Cow::Owned(data)
    };
    let mut cursor = Cursor::new(&data);
    let mut compressed = false;
    let mut language = None;
    if kind == b"iTXt" {
        let flag = cursor.number(1)?;
        let method = cursor.number(1)?;
        if flag > 1 || method != 0 {
            return Err(Error::Unsupported("PNG text compression"));
        }
        compressed = flag == 1;
        language = Some(cursor.string()?).filter(|value| !value.is_empty());
        cursor.string()?;
    } else if kind == b"zTXt" {
        if cursor.number(1)? != 0 {
            return Err(Error::Unsupported("PNG text compression"));
        }
        compressed = true;
    }
    let bytes = &data[cursor.pos..];
    let decoded;
    let text = if compressed {
        let value_limit = if is_profile {
            state.limits.read_bytes
        } else {
            state.limits.value_bytes
        };
        decoded = miniz_oxide::inflate::decompress_to_vec_zlib_with_limit(
            bytes,
            state.expansion_limit().min(value_limit),
        )
        .map_err(|e| {
            if e.status == miniz_oxide::inflate::TINFLStatus::HasMoreOutput {
                Error::Limit(if state.expansion_limit() < value_limit {
                    "expanded bytes"
                } else {
                    "compressed PNG text"
                })
            } else {
                Error::Malformed("compressed PNG text")
            }
        })?;
        state.expanded(decoded.len())?;
        &decoded[..]
    } else {
        bytes
    };
    if is_profile {
        return profile(key, text, state);
    }
    if key == b"XML:com.adobe.xmp" {
        return xmp::read(text, state);
    }
    if text.len() > state.limits.value_bytes {
        return Err(Error::Limit("PNG text"));
    }
    let text = if kind == b"iTXt" {
        Cow::Borrowed(std::str::from_utf8(text).map_err(|_| Error::Malformed("PNG UTF-8"))?)
    } else {
        let extra = text.iter().filter(|b| **b >= 128).count();
        if extra > state.limits.value_bytes - text.len() {
            return Err(Error::Limit("PNG text"));
        }
        Cow::Owned(text.iter().copied().map(char::from).collect::<String>())
    };
    let key: String = key.iter().copied().map(char::from).collect();
    if language.is_some_and(|value| value.len() > state.limits.value_bytes) {
        return Err(Error::Limit("PNG language"));
    }
    xmp::store(state, "urn:png:text", &key, &text, language, None, None)
}

fn profile(key: &[u8], text: &[u8], state: &mut State) -> Result<(), Error> {
    let mut lines = text.splitn(4, |b| *b == b'\n');
    if lines.next() != Some(b"") || lines.next().is_none() {
        return Err(Error::Malformed("PNG profile header"));
    }
    let length = lines
        .next()
        .and_then(|v| std::str::from_utf8(v).ok())
        .and_then(|v| v.trim().parse::<usize>().ok())
        .ok_or(Error::Malformed("PNG profile length"))?;
    let hex = lines.next().ok_or(Error::Malformed("PNG profile hex"))?;
    if length > hex.len() / 2 {
        return Err(Error::Malformed("PNG profile length"));
    }
    state.expanded(length)?;
    let mut bytes = Vec::with_capacity(length);
    let mut digits = hex.iter().copied().filter(|b| !b.is_ascii_whitespace());
    for _ in 0..length {
        let mut byte = 0;
        for _ in 0..2 {
            let digit = digits
                .next()
                .and_then(|v| char::from(v).to_digit(16))
                .ok_or(Error::Malformed("PNG profile hex"))?;
            byte = byte * 16 + digit as u8;
        }
        bytes.push(byte);
    }
    if digits.next().is_some() {
        return Err(Error::Malformed("PNG profile length"));
    }
    match key {
        b"Raw profile type exif" | b"Raw profile type APP1" => {
            if let Some(xml) = bytes.strip_prefix(b"http://ns.adobe.com/xap/1.0/\0") {
                return xmp::read(xml, state);
            }
            let tiff = bytes.strip_prefix(b"Exif\0\0").unwrap_or(&bytes);
            tiff::read_bytes(tiff, state)
        }
        b"Raw profile type iptc" | b"Raw profile type 8bim" => {
            if bytes.starts_with(b"\x1c") {
                iptc::read(&bytes, state)
            } else {
                photoshop::read(&bytes, state)
            }
        }
        _ => xmp::read(&bytes, state),
    }
}
