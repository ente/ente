use ente_exif::{Limits, Metadata, Mode};
use std::io::Cursor;

pub fn read(bytes: &[u8], mode: Mode) -> Metadata {
    ente_exif::read(&mut Cursor::new(bytes), mode, Limits::default()).unwrap()
}

pub fn exercise(bytes: &[u8], limits: Limits) {
    let _ = ente_exif::read(&mut Cursor::new(bytes), Mode::Summary, limits);
    let ordinary = ente_exif::read(&mut Cursor::new(bytes), Mode::Details, limits);
    if let Ok(structured) = ente_exif::read_structured(&mut Cursor::new(bytes), limits) {
        assert_eq!(ordinary.unwrap(), structured.metadata);
        assert_eq!(structured.xmp.parents.len(), structured.metadata.xmp.len());
        for (index, node) in structured.xmp.nodes.iter().enumerate() {
            assert!(node.parent.is_none_or(|parent| (parent as usize) < index));
        }
        for parent in structured.xmp.parents.iter().flatten() {
            assert!((*parent as usize) < structured.xmp.nodes.len());
        }
    }
}

pub fn child_ifd(pointer: u16, mut child: Vec<u8>) -> Vec<u8> {
    let mut result = tiff(&[(pointer, 4, 1, 26u32.to_le_bytes().to_vec())], false);
    let count = u16::from_le_bytes(child[8..10].try_into().unwrap()) as usize;
    for entry in child[10..10 + count * 12].as_chunks_mut::<12>().0 {
        let kind = u16::from_le_bytes(entry[2..4].try_into().unwrap());
        let count = u32::from_le_bytes(entry[4..8].try_into().unwrap());
        let width = match kind {
            3 | 8 => 2,
            4 | 9 | 11 | 13 => 4,
            5 | 10 | 12 => 8,
            _ => 1,
        };
        if count * width > 4 {
            let old = u32::from_le_bytes(entry[8..12].try_into().unwrap());
            entry[8..12].copy_from_slice(&(old + 18).to_le_bytes());
        }
    }
    result.extend(&child[8..]);
    result
}

pub fn tiff(entries: &[(u16, u16, u32, Vec<u8>)], big: bool) -> Vec<u8> {
    let u16 = |v: u16| {
        if big {
            v.to_be_bytes()
        } else {
            v.to_le_bytes()
        }
    };
    let u32 = |v: u32| {
        if big {
            v.to_be_bytes()
        } else {
            v.to_le_bytes()
        }
    };
    let mut result = if big {
        b"MM\0*\0\0\0\x08".to_vec()
    } else {
        b"II*\0\x08\0\0\0".to_vec()
    };
    result.extend(u16(entries.len() as u16));
    let mut values: Vec<u8> = Vec::new();
    let start = 8 + 2 + entries.len() * 12 + 4;
    for (id, kind, count, value) in entries {
        result.extend(u16(*id));
        result.extend(u16(*kind));
        result.extend(u32(*count));
        if value.len() <= 4 {
            result.extend(value);
            result.resize(result.len() + 4 - value.len(), 0);
        } else {
            result.extend(u32((start + values.len()) as u32));
            values.extend(value);
        }
    }
    result.extend([0; 4]);
    result.extend(values);
    result
}

pub fn segment(marker: u8, bytes: &[u8]) -> Vec<u8> {
    let mut result = vec![0xff, marker];
    result.extend(((bytes.len() + 2) as u16).to_be_bytes());
    result.extend(bytes);
    result
}

pub fn jpeg(exif: &[u8], xmp: &str) -> Vec<u8> {
    let mut result = vec![0xff, 0xd8];
    if !exif.is_empty() {
        result.extend(segment(0xe1, &[b"Exif\0\0".as_slice(), exif].concat()));
    }
    if !xmp.is_empty() {
        result.extend(segment(
            0xe1,
            &[b"http://ns.adobe.com/xap/1.0/\0".as_slice(), xmp.as_bytes()].concat(),
        ));
    }
    result.extend(segment(0xc0, &[8, 0, 20, 0, 30, 1, 1, 0x11, 0]));
    result.extend([0xff, 0xda, 0, 8, 1, 1, 0, 0, 63, 0, 0xff, 0xd9]);
    result
}

pub fn xmp(body: &str) -> String {
    format!(
        r#"<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:t="http://ns.adobe.com/tiff/1.0/" xmlns:e="http://ns.adobe.com/exif/1.0/" xmlns:p="http://ns.google.com/photos/1.0/panorama/" xmlns:d="http://purl.org/dc/elements/1.1/">{body}</r:Description></r:RDF>"#
    )
}

pub fn box_bytes(kind: [u8; 4], data: &[u8]) -> Vec<u8> {
    let mut result = ((data.len() + 8) as u32).to_be_bytes().to_vec();
    result.extend(kind);
    result.extend(data);
    result
}

pub fn png_chunk(kind: [u8; 4], data: &[u8]) -> Vec<u8> {
    let mut result = (data.len() as u32).to_be_bytes().to_vec();
    result.extend(kind);
    result.extend(data);
    result.extend([0; 4]);
    result
}

pub fn heif(exif: &[u8], method: u16, split: bool) -> Vec<u8> {
    let ftyp = box_bytes(*b"ftyp", b"heic\0\0\0\0mif1heic");
    let mut infe = vec![2, 0, 0, 0, 0, 2, 0, 0];
    infe.extend(b"Exif\0");
    let iinf = box_bytes(
        *b"iinf",
        &[vec![0, 0, 0, 0, 0, 1], box_bytes(*b"infe", &infe)].concat(),
    );
    let pitm = box_bytes(*b"pitm", &[0, 0, 0, 0, 0, 1]);
    let mut ispe = vec![0; 4];
    ispe.extend(800u32.to_be_bytes());
    ispe.extend(600u32.to_be_bytes());
    let clap: Vec<u8> = [640u32, 1, 480, 1, u32::MAX, 2, 0, 1]
        .into_iter()
        .flat_map(u32::to_be_bytes)
        .collect();
    let ipco = box_bytes(
        *b"ipco",
        &[
            box_bytes(*b"ispe", &ispe),
            box_bytes(*b"irot", &[1]),
            box_bytes(*b"clap", &clap),
        ]
        .concat(),
    );
    let ipma = box_bytes(*b"ipma", &[0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 3, 1, 0x82, 0x83]);
    let iprp = box_bytes(*b"iprp", &[ipco, ipma].concat());
    let data = [vec![0; 4], exif.to_vec()].concat();
    let extents = if split {
        vec![(0, 10), (10, data.len() - 10)]
    } else {
        vec![(0, data.len())]
    };
    let mut iloc = vec![1, 0, 0, 0, 0x44, 0x40, 0, 1, 0, 2];
    iloc.extend(method.to_be_bytes());
    iloc.extend([0; 2]);
    let base_position = iloc.len();
    iloc.extend([0; 4]);
    iloc.extend((extents.len() as u16).to_be_bytes());
    for (offset, size) in extents {
        iloc.extend((offset as u32).to_be_bytes());
        iloc.extend((size as u32).to_be_bytes());
    }
    if method == 0 {
        let meta_size = 12 + pitm.len() + iinf.len() + iprp.len() + 8 + iloc.len();
        iloc[base_position..base_position + 4]
            .copy_from_slice(&((ftyp.len() + meta_size + 8) as u32).to_be_bytes());
    }
    let mut meta = [vec![0; 4], pitm, iinf, iprp, box_bytes(*b"iloc", &iloc)].concat();
    if method == 1 {
        meta.extend(box_bytes(*b"idat", &data));
    }
    let mut result = [ftyp, box_bytes(*b"meta", &meta)].concat();
    if method == 0 {
        result.extend(box_bytes(*b"mdat", &data));
    }
    result
}
