#![doc = include_str!("../README.md")]
#![forbid(unsafe_code)]

mod boxes;
mod datetime;
mod dimensions;
mod gif;
mod iptc;
mod isobmff;
mod jpeg;
mod jxl;
mod metadata;
mod motion;
pub mod photo;
mod photoshop;
mod png;
mod read;
mod tags;
mod text;
mod tiff;
mod webp;
mod xmp;

pub use datetime::{DateTime, DateTimeKind, DateTimePrecision, DateTimeSource, DateTimeValue};
pub use dimensions::{CleanAperture, Dimensions, Transform};
pub use iptc::Iptc;
pub use metadata::{Location, Metadata, StructuredMetadata};
pub use motion::VideoRange;
pub use photo::CaptureDateTime;
pub use read::{Error, Issue, Limits, Statistics};
pub use tags::{Ifd, Rational, Tag, Value};
pub use text::TextEncoding;
pub use xmp::{Property, XmpNode, XmpStructure, namespace};

use std::io::{Read, Seek};
pub fn read<R: Read + Seek>(source: &mut R, mode: Mode, limits: Limits) -> Result<Metadata, Error> {
    read_with_structure(source, mode, limits, None)
}
pub fn read_structured<R: Read + Seek>(
    source: &mut R,
    limits: Limits,
) -> Result<StructuredMetadata, Error> {
    let mut xmp = XmpStructure::default();
    let metadata = read_with_structure(source, Mode::Details, limits, Some(&mut xmp))?;
    Ok(StructuredMetadata { metadata, xmp })
}

fn read_with_structure<R: Read + Seek>(
    source: &mut R,
    mode: Mode,
    limits: Limits,
    structure: Option<&mut XmpStructure>,
) -> Result<Metadata, Error> {
    let mut reader = read::Reader::new(source, limits)?;
    let mut state = read::State::new(mode, limits);
    state.structure = structure;
    let header = reader.bytes(0, reader.len.min(16) as usize)?;
    state.metadata.format = if header.starts_with(b"\xff\xd8") {
        jpeg::read(&mut reader, &mut state)?;
        Format::Jpeg
    } else if header.starts_with(b"II") || header.starts_with(b"MM") {
        let len = reader.len;
        tiff::read(&mut reader, &mut state, 0, len)?;
        Format::Tiff
    } else if header.starts_with(b"\x89PNG\r\n\x1a\n") {
        png::read(&mut reader, &mut state)?;
        Format::Png
    } else if header.starts_with(b"RIFF") && header.get(8..12) == Some(b"WEBP") {
        webp::read(&mut reader, &mut state)?;
        Format::Webp
    } else if header.starts_with(b"GIF87a") || header.starts_with(b"GIF89a") {
        gif::read(&mut reader, &mut state)?;
        Format::Gif
    } else if header.starts_with(b"\xff\x0a") || header.starts_with(jxl::SIGNATURE) {
        jxl::read(&mut reader, &mut state, header.starts_with(b"\xff\x0a"))?;
        Format::Jxl
    } else if header.get(4..8) == Some(b"ftyp") {
        isobmff::read(&mut reader, &mut state)?;
        Format::Heif
    } else {
        let utf16 = header.starts_with(b"\xff\xfe") || header.starts_with(b"\xfe\xff");
        let prefix = header.strip_prefix(b"\xef\xbb\xbf").unwrap_or(&header);
        if !utf16
            && prefix
                .iter()
                .find(|b| !b.is_ascii_whitespace())
                .is_some_and(|b| *b != b'<')
        {
            return Err(Error::Unsupported("format"));
        }
        let bytes = reader.bytes(
            0,
            usize::try_from(reader.len).map_err(|_| Error::Limit("input"))?,
        )?;
        if !utf16
            && !std::str::from_utf8(&bytes)
                .map_err(|_| Error::Unsupported("format"))?
                .trim_start_matches('\u{feff}')
                .trim_start()
                .starts_with('<')
        {
            return Err(Error::Unsupported("format"));
        }
        xmp::read(&bytes, &mut state)?;
        Format::Xmp
    };
    if state.metadata.dimensions.is_none() {
        state.metadata.dimensions = state.metadata.tiff_dimensions();
    }
    motion::read(&mut reader, &mut state)?;
    state.metadata.statistics = reader.statistics;
    Ok(state.metadata)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Summary,
    Details,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    #[default]
    Jpeg,
    Tiff,
    Heif,
    Png,
    Webp,
    Gif,
    Jxl,
    Xmp,
}
