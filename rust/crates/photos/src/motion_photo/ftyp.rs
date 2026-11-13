use super::{BUFFER_SIZE, VideoIndex};
use std::io::{self, Read};

const FTYP_BOX_MIN_SIZE: u32 = 8;

const FTYP_BOX_MAX_SIZE: u32 = 1024;

const KNOWN_VIDEO_BRANDS: &[[u8; 4]] = &[
    *b"isom", *b"iso2", *b"iso5", *b"iso6", *b"mp41", *b"mp42", *b"mp71", *b"M4V ", *b"M4VP",
    *b"avc1", *b"mmp4", *b"3gp4", *b"3gp5", *b"3gp6", *b"qt  ", *b"MSNV", *b"dash", *b"f4v ",
];

pub(super) fn find_largest_ftyp_segment<R: Read>(
    mut reader: R,
    size: usize,
) -> io::Result<Option<VideoIndex>> {
    const OVERLAP: usize = 11;
    let mut buffer = vec![0; BUFFER_SIZE + OVERLAP];
    let mut carried = 0;
    let mut offset = 0;
    let mut remaining = size;
    let mut previous_start = None;
    let mut best: Option<VideoIndex> = None;

    while remaining > 0 {
        let length = remaining.min(BUFFER_SIZE);
        reader.read_exact(&mut buffer[carried..carried + length])?;
        let available = carried + length;
        for (position, header) in buffer[..available].windows(12).enumerate() {
            if &header[4..8] != b"ftyp" {
                continue;
            }
            let start = offset + position;
            let box_size = u32::from_be_bytes([header[0], header[1], header[2], header[3]]);
            if start == 0
                || !(FTYP_BOX_MIN_SIZE..=FTYP_BOX_MAX_SIZE).contains(&box_size)
                || !KNOWN_VIDEO_BRANDS
                    .iter()
                    .any(|brand| header[8..12] == *brand)
            {
                continue;
            }
            if let Some(previous) = previous_start {
                keep_largest(&mut best, previous, start);
            }
            previous_start = Some(start);
        }
        carried = available.min(OVERLAP);
        buffer.copy_within(available - carried..available, 0);
        offset += available - carried;
        remaining -= length;
    }
    if let Some(start) = previous_start {
        keep_largest(&mut best, start, size);
    }
    Ok(best)
}

fn keep_largest(best: &mut Option<VideoIndex>, start: usize, end: usize) {
    if best
        .as_ref()
        .is_none_or(|index| end - start > index.end - index.start)
    {
        *best = Some(VideoIndex { start, end });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn recognizes_headers_across_chunks_and_keeps_first_on_ties() {
        let header = b"\0\0\0\x10ftypmp42\0\0\0\0";
        for boundary in [1, 3, 5] {
            for split in 0..12 {
                let start = BUFFER_SIZE * boundary - split;
                let mut source = vec![0; start];
                source.extend_from_slice(header);
                source.extend_from_slice(header);
                assert_eq!(
                    find_largest_ftyp_segment(Cursor::new(&source), source.len()).unwrap(),
                    Some(VideoIndex {
                        start,
                        end: start + header.len()
                    }),
                    "header split at {split} near chunk {boundary}"
                );
            }
        }
    }

    #[test]
    fn limits_read_requests_and_reports_truncated_input() {
        struct ShortReads(Cursor<Vec<u8>>);
        impl Read for ShortReads {
            fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
                assert!(buffer.len() <= BUFFER_SIZE);
                let length = buffer.len().min(17);
                self.0.read(&mut buffer[..length])
            }
        }
        let length = BUFFER_SIZE * 3 + 7;
        let mut reader = ShortReads(Cursor::new(vec![0; length]));
        assert_eq!(
            find_largest_ftyp_segment(&mut reader, length).unwrap(),
            None
        );
        assert_eq!(reader.0.position(), length as u64);
        let error = find_largest_ftyp_segment(Cursor::new([0; 12]), 13).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::UnexpectedEof);
    }
}
