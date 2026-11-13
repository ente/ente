use crate::boxes::{BoxRange, box_at};
use crate::read::{Cursor, Error, Reader, State, be32, range};
use crate::{CleanAperture, Dimensions, Rational, Transform, tiff, xmp};
use std::collections::BTreeMap;
use std::io::{Read, Seek};

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
) -> Result<(), Error> {
    let first = box_at(reader, 0, reader.len)?;
    let brands = reader.bytes(
        first.start,
        usize::try_from(first.len).map_err(|_| Error::Limit("brands"))?,
    )?;
    if brands.len() < 8
        || !brands.as_chunks::<4>().0.iter().enumerate().any(|(i, b)| {
            i != 1
                && matches!(
                    b,
                    b"heic" | b"heix" | b"hevc" | b"hevx" | b"mif1" | b"msf1" | b"avif" | b"avis"
                )
        })
    {
        return Err(Error::Unsupported("ISOBMFF image brand"));
    }
    let mut offset = first.end();
    while offset < reader.len {
        state.entries(1)?;
        let b = box_at(reader, offset, reader.len)?;
        if &b.kind == b"meta" {
            return metadata(reader, state, b);
        }
        offset = b.end();
    }
    Err(Error::Malformed("missing HEIF metadata"))
}

#[derive(Default)]
struct Item {
    kind: [u8; 4],
    mime: String,
    protected: bool,
    location: Option<Location>,
    describes: Vec<u32>,
}
struct Location {
    method: u64,
    reference: u64,
    base: u64,
    extents: Vec<(u64, u64)>,
}
#[derive(Default)]
struct Meta {
    primary: Option<u32>,
    items: BTreeMap<u32, Item>,
    properties: Vec<BoxRange>,
    associations: Vec<(u32, Vec<(usize, bool)>)>,
    idat: Option<BoxRange>,
}

fn metadata<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    b: BoxRange,
) -> Result<(), Error> {
    range(b.start, b.len, 0, 4)?;
    let mut meta = Meta::default();
    let mut offset = b.start + 4;
    while offset < b.end() {
        state.entries(1)?;
        let child = box_at(reader, offset, b.end())?;
        offset = child.end();
        match &child.kind {
            b"pitm" => {
                let bytes = payload(reader, &child)?;
                let mut c = Cursor::new(&bytes);
                let version = c.number(1)?;
                c.take(3)?;
                if version > 1 {
                    return Err(Error::Unsupported("pitm version"));
                }
                meta.primary = Some(c.number(if version == 0 { 2 } else { 4 })? as u32);
            }
            b"iinf" => item_info(reader, state, &child, &mut meta)?,
            b"iloc" => locations(&payload(reader, &child)?, state, &mut meta)?,
            b"iref" => references(reader, state, &child, &mut meta)?,
            b"iprp" => properties(reader, state, &child, &mut meta)?,
            b"idat" => meta.idat = Some(child),
            _ => {}
        }
    }
    let primary = meta.primary.ok_or(Error::Malformed("primary image"))?;
    for (_, props) in meta.associations.iter().filter(|(id, _)| *id == primary) {
        for &(index, _) in props {
            if index == 0 {
                continue;
            }
            let p = meta
                .properties
                .get(index - 1)
                .ok_or(Error::Malformed("property index"))?;
            match &p.kind {
                b"ispe" => {
                    if p.len != 12 {
                        return Err(Error::Malformed("ispe size"));
                    }
                    let bytes = reader.array::<8>(p.start + 4)?;
                    state.metadata.dimensions = Dimensions::new(be32(&bytes), be32(&bytes[4..]));
                }
                b"irot" | b"imir" => {
                    if p.len != 1 {
                        return Err(Error::Malformed("transform size"));
                    }
                    let value = reader.array::<1>(p.start)?[0];
                    let transform = if &p.kind == b"irot" && value <= 3 {
                        Transform::Rotate(value)
                    } else if &p.kind == b"imir" && value <= 1 {
                        Transform::Mirror(value)
                    } else {
                        return Err(Error::Malformed("transform value"));
                    };
                    state.retain(std::mem::size_of::<Transform>())?;
                    state.metadata.transforms.push(transform);
                }
                b"clap" => {
                    if p.len != 32 {
                        return Err(Error::Malformed("clap size"));
                    }
                    let bytes = reader.array::<32>(p.start)?;
                    let rational = |offset, signed| -> Result<Rational, Error> {
                        let n = be32(&bytes[offset..]);
                        let d = be32(&bytes[offset + 4..]);
                        if d == 0 {
                            return Err(Error::Malformed("clap denominator"));
                        }
                        Ok(Rational {
                            numerator: if signed {
                                i64::from(n as i32)
                            } else {
                                i64::from(n)
                            },
                            denominator: i64::from(d),
                        })
                    };
                    let crop = CleanAperture {
                        width: rational(0, false)?,
                        height: rational(8, false)?,
                        horizontal_offset: rational(16, true)?,
                        vertical_offset: rational(24, true)?,
                    };
                    state.retain(std::mem::size_of::<Transform>())?;
                    state.metadata.transforms.push(Transform::Crop(crop));
                }
                _ => {}
            }
        }
    }
    for is_exif in [true, false] {
        let candidates = meta.items.values().filter(|item| {
            if is_exif {
                &item.kind == b"Exif"
            } else {
                &item.kind == b"mime"
                    && matches!(
                        item.mime.as_str(),
                        "application/rdf+xml" | "application/xml" | "text/xml"
                    )
            }
        });
        let has_primary = candidates
            .clone()
            .any(|item| item.describes.contains(&primary));
        let mut candidates = candidates.filter(|item| {
            if has_primary {
                item.describes.contains(&primary)
            } else {
                item.describes.is_empty()
            }
        });
        let Some(item) = candidates.next() else {
            continue;
        };
        if candidates.next().is_some() {
            state.recover(
                b.start,
                Err(Error::Unsupported("ambiguous primary metadata")),
            )?;
            continue;
        }
        let result = read_item(reader, state, item, meta.idat.as_ref(), is_exif);
        state.recover(b.start, result)?;
    }
    Ok(())
}

fn read_item<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    item: &Item,
    idat: Option<&BoxRange>,
    is_exif: bool,
) -> Result<(), Error> {
    if item.protected {
        return Err(Error::Unsupported("protected metadata"));
    }
    let location = item
        .location
        .as_ref()
        .ok_or(Error::Malformed("missing item location"))?;
    if location.reference != 0 {
        return Err(Error::Unsupported("external item reference"));
    }
    let (origin, len) = match location.method {
        0 => (0, reader.len),
        1 => {
            let b = idat.ok_or(Error::Malformed("missing idat"))?;
            (b.start, b.len)
        }
        _ => return Err(Error::Unsupported("item construction method")),
    };
    if location.extents.is_empty() {
        return Err(Error::Malformed("missing item extents"));
    }
    let extent = |(offset, size)| {
        if size == 0 {
            return Err(Error::Unsupported("unbounded item extent"));
        }
        let offset = location
            .base
            .checked_add(offset)
            .ok_or(Error::Malformed("extent offset overflow"))?;
        Ok((range(origin, len, offset, size)?, size))
    };
    if is_exif && let [single] = location.extents.as_slice() {
        let (start, len) = extent(*single)?;
        return tiff::exif_block(reader, state, start, len);
    }
    let total = location.extents.iter().try_fold(0u64, |sum, (_, size)| {
        sum.checked_add(*size)
            .ok_or(Error::Malformed("extent length overflow"))
    })?;
    if total > state.limits.read_bytes as u64 {
        return Err(Error::Limit("item bytes"));
    }
    let mut bytes = Vec::with_capacity(total as usize);
    for &item in &location.extents {
        let (absolute, size) = extent(item)?;
        let previous = bytes.len();
        bytes.resize(previous + size as usize, 0);
        reader.fill(absolute, &mut bytes[previous..])?;
    }
    if is_exif {
        let mut cursor = std::io::Cursor::new(&bytes);
        let mut buffer = Reader::new(&mut cursor, state.limits)?;
        tiff::exif_block(&mut buffer, state, 0, total)
    } else {
        xmp::read(&bytes, state)
    }
}

fn item_info<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    b: &BoxRange,
    meta: &mut Meta,
) -> Result<(), Error> {
    if b.len < 6 {
        return Err(Error::Malformed("iinf header"));
    }
    let version = reader.array::<1>(b.start)?[0];
    let width = if version == 0 { 2 } else { 4 };
    let bytes = reader.bytes(b.start + 4, width)?;
    let count = Cursor::new(&bytes).number(width)? as usize;
    state.entries(count)?;
    let mut offset = b.start + 4 + width as u64;
    for _ in 0..count {
        let child = box_at(reader, offset, b.end())?;
        offset = child.end();
        if &child.kind != b"infe" {
            return Err(Error::Malformed("item info box"));
        }
        let bytes = payload(reader, &child)?;
        let mut c = Cursor::new(&bytes);
        let version = c.number(1)?;
        c.take(3)?;
        if !matches!(version, 2 | 3) {
            return Err(Error::Unsupported("infe version"));
        }
        let id = c.number(if version == 2 { 2 } else { 4 })? as u32;
        let protection = c.number(2)?;
        #[expect(
            clippy::expect_used,
            reason = "take returns exactly the requested four bytes"
        )]
        let kind: [u8; 4] = c.take(4)?.try_into().expect("item type is four bytes");
        c.string()?;
        let mime = if &kind == b"mime" {
            c.string()?.to_owned()
        } else {
            String::new()
        };
        let item = meta.items.entry(id).or_default();
        if item.kind != [0; 4] {
            return Err(Error::Malformed("duplicate item info"));
        }
        item.kind = kind;
        item.mime = mime;
        item.protected = protection != 0;
    }
    Ok(())
}

fn locations(bytes: &[u8], state: &mut State, meta: &mut Meta) -> Result<(), Error> {
    let mut c = Cursor::new(bytes);
    let version = c.number(1)?;
    if version > 2 {
        return Err(Error::Unsupported("iloc version"));
    }
    c.take(3)?;
    let sizes = c.number(1)? as usize;
    let more = c.number(1)? as usize;
    let (offset_size, length_size, base_size, index_size) = (
        sizes >> 4,
        sizes & 15,
        more >> 4,
        if version == 0 { 0 } else { more & 15 },
    );
    let count = c.number(if version < 2 { 2 } else { 4 })? as usize;
    state.entries(count)?;
    for _ in 0..count {
        let id = c.number(if version < 2 { 2 } else { 4 })? as u32;
        let method = if version == 0 { 0 } else { c.number(2)? & 15 };
        let reference = c.number(2)?;
        let base = c.number(base_size)?;
        let count = c.number(2)? as usize;
        state.entries(count)?;
        let mut extents = Vec::new();
        for _ in 0..count {
            c.number(index_size)?;
            extents.push((c.number(offset_size)?, c.number(length_size)?));
        }
        let item = meta.items.entry(id).or_default();
        if item.location.is_some() {
            return Err(Error::Malformed("duplicate item location"));
        }
        item.location = Some(Location {
            method,
            reference,
            base,
            extents,
        });
    }
    Ok(())
}

fn references<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    b: &BoxRange,
    meta: &mut Meta,
) -> Result<(), Error> {
    if b.len < 4 {
        return Err(Error::Malformed("iref header"));
    }
    let version = reader.array::<1>(b.start)?[0];
    if version > 1 {
        return Err(Error::Unsupported("iref version"));
    }
    let width = if version == 0 { 2 } else { 4 };
    let mut offset = b.start + 4;
    while offset < b.end() {
        state.entries(1)?;
        let child = box_at(reader, offset, b.end())?;
        offset = child.end();
        if &child.kind != b"cdsc" {
            continue;
        }
        let bytes = payload(reader, &child)?;
        let mut c = Cursor::new(&bytes);
        let id = c.number(width)? as u32;
        let count = c.number(2)? as usize;
        state.entries(count)?;
        let item = meta.items.entry(id).or_default();
        for _ in 0..count {
            item.describes.push(c.number(width)? as u32);
        }
    }
    Ok(())
}

fn properties<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    b: &BoxRange,
    meta: &mut Meta,
) -> Result<(), Error> {
    let mut offset = b.start;
    while offset < b.end() {
        state.entries(1)?;
        let child = box_at(reader, offset, b.end())?;
        offset = child.end();
        match &child.kind {
            b"ipco" => {
                let mut offset = child.start;
                while offset < child.end() {
                    state.entries(1)?;
                    let property = box_at(reader, offset, child.end())?;
                    offset = property.end();
                    meta.properties.push(property);
                }
            }
            b"ipma" => {
                let bytes = payload(reader, &child)?;
                let mut c = Cursor::new(&bytes);
                let version = c.number(1)?;
                if version > 1 {
                    return Err(Error::Unsupported("ipma version"));
                }
                let flags = c.number(3)?;
                let count = c.number(4)? as usize;
                state.entries(count)?;
                for _ in 0..count {
                    let id = c.number(if version == 0 { 2 } else { 4 })? as u32;
                    let count = c.number(1)? as usize;
                    state.entries(count)?;
                    let mut properties = Vec::new();
                    for _ in 0..count {
                        let width = if flags & 1 == 0 { 1 } else { 2 };
                        let value = c.number(width)? as usize;
                        let mask = 1 << (width * 8 - 1);
                        properties.push((value & (mask - 1), value & mask != 0));
                    }
                    meta.associations.push((id, properties));
                }
            }
            _ => {}
        }
    }
    Ok(())
}

fn payload<R: Read + Seek>(reader: &mut Reader<'_, R>, b: &BoxRange) -> Result<Vec<u8>, Error> {
    reader.bytes(
        b.start,
        usize::try_from(b.len).map_err(|_| Error::Limit("box payload"))?,
    )
}
