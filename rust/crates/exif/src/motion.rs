use crate::boxes::box_at;
use crate::read::{Error, Reader, State, be32, le32, range};
use crate::{Format, namespace};
use std::io::{Read, Seek};
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VideoRange {
    pub start: u64,
    pub end: u64,
}

pub(crate) fn read<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
) -> Result<(), Error> {
    if !matches!(state.metadata.format, Format::Jpeg | Format::Heif) || reader.len < 8 {
        return Ok(());
    }
    if matches!(state.metadata.property(namespace::CAMERA, "MotionPhoto"), Some(value) if value != "1")
    {
        return Ok(());
    }
    let footer = reader.array::<8>(reader.len - 8)?;
    let mut starts = Vec::new();
    let result = samsung(reader, state, footer, &mut starts);
    state.recover(reader.len - 8, result)?;
    let result = oplus(reader, state, footer, &mut starts);
    state.recover(reader.len - 8, result)?;
    let result = xmp_starts(state, reader.len, &mut starts);
    state.recover(0, result)?;
    if state.metadata.format == Format::Heif {
        let result = mpvd(reader, state, &mut starts);
        state.recover(0, result)?;
    }
    starts.sort_unstable();
    starts.dedup();
    let mut videos = Vec::new();
    for start in starts {
        if start == 0 || reader.len.saturating_sub(start) < 16 {
            continue;
        }
        let result = video_starts(reader, state, start, &mut videos);
        state.recover(start, result)?;
    }
    videos.sort_unstable();
    videos.dedup();
    state.metadata.motion_video = videos
        .iter()
        .enumerate()
        .map(|(i, start)| VideoRange {
            start: *start,
            end: videos.get(i + 1).copied().unwrap_or(reader.len),
        })
        .max_by_key(|v| v.end - v.start);
    Ok(())
}

fn xmp_starts(state: &State, len: u64, starts: &mut Vec<u64>) -> Result<(), Error> {
    let mut end = len;
    let mut items: Vec<u32> = state
        .metadata
        .xmp
        .iter()
        .filter(|p| p.namespace == namespace::ITEM)
        .filter_map(|p| p.item)
        .collect();
    items.sort_unstable();
    items.dedup();
    for item in items.into_iter().rev() {
        let property = |name| {
            state
                .metadata
                .xmp
                .iter()
                .find(|p| p.namespace == namespace::ITEM && p.item == Some(item) && p.name == name)
                .map(|p| p.value.as_str())
        };
        if property("Semantic") == Some("Primary") {
            continue;
        }
        let length = property("Length")
            .unwrap_or("0")
            .parse::<u64>()
            .map_err(|_| Error::Malformed("motion item length"))?;
        if length > end {
            return Err(Error::Malformed("motion item length"));
        }
        end -= length;
        if property("Semantic") == Some("MotionPhoto")
            && matches!(property("Mime"), Some("video/mp4" | "video/quicktime"))
            && length != 0
        {
            starts.push(end);
        }
    }
    if let Some(offset) = state
        .metadata
        .property(namespace::CAMERA, "MicroVideoOffset")
        .and_then(|s| s.parse::<u64>().ok())
        && offset != 0
        && offset < len
    {
        starts.push(len - offset);
    }
    Ok(())
}

fn oplus<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    footer: [u8; 8],
    starts: &mut Vec<u64>,
) -> Result<(), Error> {
    if &footer[..4] != b"jxrs" {
        return Ok(());
    }
    let len = u64::from(le32(&footer[4..]));
    if len < 8 {
        return Err(Error::Malformed("JXRS length"));
    }
    if len > state.limits.value_bytes as u64 {
        return Err(Error::Limit("JXRS index"));
    }
    let base = reader
        .len
        .checked_sub(len)
        .ok_or(Error::Malformed("JXRS length"))?;
    let bytes = reader.bytes(base, (len - 8) as usize)?;
    let bytes = bytes.strip_suffix(&[0]).unwrap_or(&bytes);
    let json: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| Error::Malformed("JXRS JSON"))?;
    let mut pending = vec![(&json, 0)];
    while let Some((value, depth)) = pending.pop() {
        state.entries(1)?;
        if depth > state.limits.depth {
            return Err(Error::Limit("JSON depth"));
        }
        match value {
            serde_json::Value::Array(items) => pending.extend(items.iter().map(|v| (v, depth + 1))),
            serde_json::Value::Object(items) => {
                pending.extend(items.values().map(|v| (v, depth + 1)))
            }
            _ => {}
        }
    }
    for item in json
        .as_array()
        .ok_or(Error::Malformed("JXRS index array"))?
    {
        if item["name"] != "live.subVideo" {
            continue;
        }
        let offset = item["offset"]
            .as_u64()
            .ok_or(Error::Malformed("JXRS offset"))?;
        let len = item["length"]
            .as_u64()
            .ok_or(Error::Malformed("JXRS video length"))?;
        let start = base
            .checked_sub(offset)
            .ok_or(Error::Malformed("JXRS video offset"))?;
        range(0, base, start, len)?;
        starts.push(start);
    }
    Ok(())
}

fn samsung<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    footer: [u8; 8],
    starts: &mut Vec<u64>,
) -> Result<(), Error> {
    if &footer[4..] != b"SEFT" {
        return Ok(());
    }
    let len = u64::from(le32(&footer));
    let start = reader
        .len
        .checked_sub(len + 8)
        .ok_or(Error::Malformed("SEF footer"))?;
    if len < 12 {
        return Err(Error::Malformed("SEF directory"));
    }
    let header = reader.array::<12>(start)?;
    if &header[..4] != b"SEFH" {
        return Err(Error::Malformed("SEF signature"));
    }
    let count = le32(&header[8..]) as usize;
    state.entries(count)?;
    if count as u64 * 12 != len - 12 {
        return Err(Error::Malformed("SEF entry count"));
    }
    let entries = reader.bytes(start + 12, count * 12)?;
    for entry in entries.as_chunks::<12>().0 {
        let kind = u16::from_le_bytes([entry[2], entry[3]]);
        if !matches!(kind, 0x0a30 | 0x0a33) {
            continue;
        }
        let position = start
            .checked_sub(u64::from(le32(&entry[4..])))
            .ok_or(Error::Malformed("SEF record offset"))?;
        let size = u64::from(le32(&entry[8..]));
        range(0, start, position, size)?;
        if size < 8 {
            return Err(Error::Malformed("SEF record"));
        }
        let header = reader.array::<8>(position)?;
        let name_len = u64::from(le32(&header[4..]));
        range(position, size, 8, name_len + 12)?;
        if name_len > 64 {
            return Err(Error::Malformed("SEF record name"));
        }
        let name = reader.bytes(position + 8, name_len as usize)?;
        if !matches!(
            name.as_slice(),
            b"MotionPhoto_Data" | b"MotionPhoto_AutoPlay"
        ) {
            continue;
        }
        let data = position + 8 + name_len;
        let header = reader.array::<12>(data)?;
        if &header[..4] == b"mpv2" {
            let offset = u64::from(be32(&header[4..]));
            let length = u64::from(be32(&header[8..]));
            range(0, reader.len, offset, length)?;
            starts.push(offset);
        } else if &header[4..8] == b"ftyp" {
            starts.push(data);
        }
    }
    Ok(())
}

fn mpvd<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    starts: &mut Vec<u64>,
) -> Result<(), Error> {
    let mut offset = 0;
    while reader.len - offset >= 8 {
        state.entries(1)?;
        let b = match box_at(reader, offset, reader.len) {
            Ok(b) => b,
            Err(Error::Malformed(_)) => break,
            Err(e) => return Err(e),
        };
        if &b.kind == b"mpvd" {
            starts.push(b.start);
        }
        offset = b.end();
    }
    Ok(())
}

fn video_starts<R: Read + Seek>(
    reader: &mut Reader<'_, R>,
    state: &mut State,
    start: u64,
    videos: &mut Vec<u64>,
) -> Result<(), Error> {
    let first = reader.array::<12>(start)?;
    if &first[4..8] != b"ftyp" {
        return Ok(());
    }
    let mut offset = start;
    let mut current = None;
    let mut moov = false;
    let mut mdat = false;
    while reader.len - offset >= 8 {
        state.entries(1)?;
        let b = match box_at(reader, offset, reader.len) {
            Ok(b) => b,
            Err(Error::Malformed(_)) if moov && mdat => break,
            Err(e) => return Err(e),
        };
        match &b.kind {
            b"ftyp" => {
                if moov
                    && mdat
                    && let Some(start) = current
                {
                    videos.push(start);
                }
                if b.len < 8 || b.len % 4 != 0 {
                    return Err(Error::Malformed("video ftyp"));
                }
                let mut supported = false;
                for position in std::iter::once(0).chain((8..b.len).step_by(4)) {
                    let brand = reader.array::<4>(b.start + position)?;
                    if matches!(
                        &brand,
                        b"isom"
                            | b"iso2"
                            | b"iso5"
                            | b"iso6"
                            | b"mp41"
                            | b"mp42"
                            | b"avc1"
                            | b"qt  "
                            | b"M4V "
                            | b"3gp4"
                            | b"3gp5"
                    ) {
                        supported = true;
                        break;
                    }
                }
                if !supported {
                    break;
                }
                current = Some(offset);
                moov = false;
                mdat = false;
            }
            b"moov" => moov = true,
            b"mdat" => mdat = true,
            _ => {}
        }
        offset = b.end();
    }
    if moov
        && mdat
        && let Some(start) = current
    {
        videos.push(start);
    }
    Ok(())
}
