use super::common::{self, box_bytes, read, tiff, xmp};
use ente_exif::{Dimensions, Error, Format, Limits, Mode, Transform};
use std::io::Cursor;

#[test]
fn raw_headers_cover_size_encodings_ratios_and_orientations() {
    for (height, width, selector) in [
        (129, 257, 0),
        (3001, 5001, 1),
        (65539, 90001, 2),
        (1 << 29, 1 << 30, 3),
    ] {
        let bytes = header(false, height, width, 0, selector, None);
        let metadata = read(&bytes, Mode::Summary);
        assert_eq!(metadata.format, Format::Jxl);
        assert_eq!(metadata.dimensions, Some(Dimensions { width, height }));
        assert_eq!(metadata.display_dimensions(), metadata.dimensions);
    }
    for (ratio, width) in [
        (1, 120),
        (2, 144),
        (3, 160),
        (4, 180),
        (5, 213),
        (6, 150),
        (7, 240),
    ] {
        let metadata = read(&header(true, 120, 0, ratio, 0, None), Mode::Summary);
        assert_eq!(metadata.dimensions, Some(Dimensions { width, height: 120 }));
    }
    for orientation in 1..=8 {
        let metadata = read(
            &header(true, 24, 40, 0, 0, Some(orientation)),
            Mode::Summary,
        );
        assert_eq!(metadata.transforms, [Transform::Orientation(orientation)]);
        let expected = if orientation >= 5 {
            Dimensions {
                width: 24,
                height: 40,
            }
        } else {
            Dimensions {
                width: 40,
                height: 24,
            }
        };
        assert_eq!(metadata.display_dimensions(), Some(expected));
    }
    assert_eq!(
        read(&header(true, 24, 40, 0, 0, Some(0)), Mode::Summary).transforms,
        [Transform::Orientation(1)]
    );
}

#[test]
fn codestream_wins_over_stale_exif_size_and_orientation() {
    let exif = tiff(
        &[
            (0x100, 4, 1, 4032u32.to_le_bytes().to_vec()),
            (0x101, 4, 1, 3024u32.to_le_bytes().to_vec()),
            (0x10f, 2, 6, b"Maker\0".to_vec()),
            (0x112, 3, 1, 6u16.to_le_bytes().to_vec()),
        ],
        false,
    );
    let exif = [2u32.to_be_bytes().as_slice(), b"--", &exif].concat();
    for orientation in [None, Some(1), Some(6)] {
        let bytes = container(&[
            box_bytes(*b"Exif", &exif),
            box_bytes(*b"jxlc", &header(false, 173, 211, 0, 0, orientation)),
            box_bytes(
                *b"xml ",
                xmp("<d:description>coast</d:description>").as_bytes(),
            ),
        ]);
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(&bytes, mode);
            assert!(metadata.issues.is_empty());
            assert_eq!(metadata.width(), Some(211));
            assert_eq!(metadata.height(), Some(173));
            assert_eq!(metadata.orientation(), Some(6));
            assert_eq!(metadata.camera_make(), Some("Maker"));
            assert_eq!(metadata.xmp_description(None), Some("coast"));
            let expected = if orientation == Some(6) {
                Dimensions {
                    width: 173,
                    height: 211,
                }
            } else {
                Dimensions {
                    width: 211,
                    height: 173,
                }
            };
            assert_eq!(metadata.display_dimensions(), Some(expected));
        }
    }
}

#[test]
fn split_headers_can_cross_every_byte_boundary() {
    let stream = header(false, 400001, 500001, 0, 3, Some(8));
    for split in 0..=stream.len() {
        let bytes = container(&[
            part(0, &stream[..split]),
            box_bytes(
                *b"xml ",
                xmp("<d:description>between parts</d:description>").as_bytes(),
            ),
            part(1, &[]),
            part(0x8000_0002, &stream[split..]),
        ]);
        let metadata = read(&bytes, Mode::Summary);
        assert_eq!(
            metadata.display_dimensions(),
            Some(Dimensions {
                width: 400001,
                height: 500001
            })
        );
        assert_eq!(metadata.xmp_description(None), Some("between parts"));
    }
}

#[test]
fn extended_and_to_eof_boxes_skip_pixel_payloads() {
    let mut stream = header(false, 71, 113, 0, 0, None);
    stream.resize(500_000, 0);
    for size in [0u32, 1] {
        let mut body = size.to_be_bytes().to_vec();
        body.extend(b"jxlc");
        if size == 1u32 {
            body.extend((16 + stream.len() as u64).to_be_bytes());
        }
        body.extend(&stream);
        let metadata = read(&container(&[body]), Mode::Summary);
        assert_eq!(
            metadata.dimensions,
            Some(Dimensions {
                width: 113,
                height: 71
            })
        );
        assert!(metadata.statistics.bytes_read < 80);
    }
}

#[test]
fn invalid_box_sizes_and_codestream_sequences_fail() {
    let stream = header(true, 24, 40, 0, 0, None);
    for boxes in [
        vec![],
        vec![part(0, &stream)],
        vec![part(0x8000_0001, &stream)],
        vec![part(0, &stream), part(0x8000_0000, &[])],
        vec![part(0x8000_0000, &stream), part(0x8000_0001, &[])],
        vec![part(0, &stream), box_bytes(*b"jxlc", &stream)],
        vec![box_bytes(*b"jxlc", &stream), box_bytes(*b"jxlc", &stream)],
        vec![box_bytes(*b"jxlp", &[0, 0, 0])],
        vec![b"\0\0\0\x07jxlc".to_vec()],
        vec![b"\0\0\0\x01jxlc\0\0\0\0\0\0\0\x0f".to_vec()],
        vec![b"\0\0\0\x01jxlc\xff\xff\xff\xff\xff\xff\xff\xff".to_vec()],
    ] {
        assert!(matches!(
            ente_exif::read(
                &mut Cursor::new(container(&boxes)),
                Mode::Summary,
                Limits::default()
            ),
            Err(Error::Malformed(_))
        ));
    }
}

#[test]
fn brotli_metadata_uses_the_same_exif_and_xmp_paths() {
    let exif = [
        vec![0; 4],
        tiff(&[(0x10f, 2, 6, b"Maker\0".to_vec())], true),
    ]
    .concat();
    let xml = xmp("<d:description>星空</d:description>");
    let bytes = container(&[
        box_bytes(*b"jxlc", &header(true, 24, 40, 0, 0, None)),
        brob(*b"Exif", &stored_brotli(&exif)),
        brob(*b"xml ", &stored_brotli(xml.as_bytes())),
    ]);
    for mode in [Mode::Summary, Mode::Details] {
        let metadata = read(&bytes, mode);
        assert!(metadata.issues.is_empty(), "{:?}", metadata.issues);
        assert_eq!(metadata.camera_make(), Some("Maker"));
        assert_eq!(metadata.xmp_description(None), Some("星空"));
    }
}

#[test]
fn compressed_output_grows_within_an_aggregate_budget() {
    const COMPRESSED: &[u8] = &[
        0x42, 0x9e, 0x13, 0x80, 0x9c, 0x5b, 0x4b, 0xf5, 0x25, 0x9f, 0x46, 0x2c, 0x31, 0xd6, 0x09,
        0xed, 0x35, 0x99, 0xeb, 0xe4, 0x00, 0x0f, 0xe8, 0xb5, 0x24, 0xf0, 0x92, 0x08, 0x03, 0x4a,
        0x13, 0x0a, 0x00, 0x03, 0x0c, 0xc8, 0x72, 0x1b, 0x7b, 0x6e, 0x47, 0x51, 0x09, 0x42, 0xa7,
        0xd3, 0xe8, 0x0e, 0x93, 0x63, 0xfa, 0x13, 0xd5, 0x0e, 0x5f, 0x6d, 0x67, 0x32, 0x23, 0x3b,
        0x10, 0xdc, 0xb3, 0x92, 0x2a, 0x1c, 0xfd, 0x08, 0xe7, 0xbf, 0x5c, 0xcd, 0x07, 0xcb, 0x59,
        0x57, 0xc1, 0x1d, 0x46, 0xb6, 0x34, 0x42, 0x1f, 0xdb, 0x7d, 0x4c, 0xf0, 0xbe, 0x23, 0x61,
        0x1b, 0x12, 0x14, 0xaa, 0x82, 0xeb, 0x4d, 0x5f, 0xad, 0xc1, 0x81, 0xe6, 0x74, 0x94, 0xa8,
        0x8e, 0x46, 0x70, 0xec, 0xf3, 0x27, 0x01, 0x72, 0x4c, 0xa1, 0x20,
    ];
    let stream = box_bytes(*b"jxlc", &header(true, 24, 40, 0, 0, None));
    let encoded = brob(*b"xml ", COMPRESSED);
    let plain = br#"<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:d="http://purl.org/dc/elements/1.1/"><d:description>woods</d:description></r:Description></r:RDF>"#;
    let exact = plain.len() + 40000;
    let mut limits = Limits {
        read_bytes: 65536,
        ..Default::default()
    };
    let metadata = ente_exif::read(
        &mut Cursor::new(container(&[stream.clone(), encoded.clone()])),
        Mode::Summary,
        limits,
    )
    .unwrap();
    assert!(metadata.issues.is_empty());
    assert_eq!(metadata.xmp_description(None), Some("woods"));
    assert!(metadata.statistics.bytes_read < 300);
    let repeated = container(&[stream, encoded.clone(), encoded]);
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&repeated), Mode::Summary, limits),
        Err(Error::Limit("Brotli output"))
    ));
    limits.read_bytes = exact * 2;
    assert!(ente_exif::read(&mut Cursor::new(&repeated), Mode::Summary, limits).is_ok());
    limits.read_bytes -= 1;
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(&repeated), Mode::Summary, limits),
        Err(Error::Limit("Brotli output"))
    ));
}

#[test]
fn malformed_compressed_metadata_recovers_but_limits_stop() {
    let xml = xmp("<d:description>after</d:description>");
    let compressed = stored_brotli(xml.as_bytes());
    for bad in [
        compressed[..compressed.len() - 1].to_vec(),
        [compressed.clone(), vec![0]].concat(),
        vec![0x11],
        vec![],
    ] {
        let metadata = read(
            &container(&[
                box_bytes(*b"jxlc", &header(true, 24, 40, 0, 0, None)),
                brob(*b"xml ", &bad),
                box_bytes(*b"xml ", xml.as_bytes()),
            ]),
            Mode::Summary,
        );
        assert_eq!(metadata.issues.len(), 1);
        assert_eq!(metadata.xmp_description(None), Some("after"));
    }
    let bytes = container(&[
        box_bytes(*b"jxlc", &header(true, 24, 40, 0, 0, None)),
        brob(*b"xml ", &[0x0f]),
    ]);
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(bytes), Mode::Summary, Limits::default()),
        Err(Error::Limit("Brotli window"))
    ));
}

#[test]
fn unknown_boxes_are_skipped_and_brob_cannot_wrap_codestreams() {
    let metadata = read(
        &container(&[
            box_bytes(*b"jxlc", &header(true, 24, 40, 0, 0, None)),
            brob(*b"jumb", &[0x11]),
            brob(*b"brob", &[]),
            brob(*b"jxlc", &[]),
            box_bytes(*b"free", &vec![0; 10000]),
        ]),
        Mode::Summary,
    );
    assert_eq!(metadata.issues.len(), 2);
    assert!(metadata.statistics.bytes_read < 120);
}

#[test]
fn header_truncations_and_mutations_remain_bounded() {
    let bytes = container(&[
        part(0, &[0xff]),
        part(
            0x8000_0001,
            &header(false, 400001, 500001, 0, 3, Some(7))[1..],
        ),
        brob(
            *b"xml ",
            &stored_brotli(xmp("<d:description>green</d:description>").as_bytes()),
        ),
    ]);
    for end in 0..bytes.len() {
        common::exercise(&bytes[..end], Limits::default());
    }
    for index in 0..bytes.len() {
        let mut changed = bytes.clone();
        changed[index] ^= 0xff;
        common::exercise(&changed, Limits::default());
        common::exercise(
            &changed,
            Limits {
                read_bytes: 256,
                entries: 8,
                output_bytes: 512,
                ..Default::default()
            },
        );
    }
}

fn container(boxes: &[Vec<u8>]) -> Vec<u8> {
    [
        b"\0\0\0\x0cJXL \r\n\x87\n".to_vec(),
        box_bytes(*b"ftyp", b"jxl \0\0\0\0jxl "),
        boxes.concat(),
    ]
    .concat()
}

fn part(index: u32, bytes: &[u8]) -> Vec<u8> {
    box_bytes(*b"jxlp", &[index.to_be_bytes().as_slice(), bytes].concat())
}

fn brob(kind: [u8; 4], bytes: &[u8]) -> Vec<u8> {
    box_bytes(*b"brob", &[kind.as_slice(), bytes].concat())
}

fn header(
    div8: bool,
    height: u32,
    width: u32,
    ratio: u32,
    selector: u32,
    orientation: Option<u8>,
) -> Vec<u8> {
    let mut bits = Vec::new();
    put(&mut bits, 0x0aff, 16);
    put(&mut bits, u32::from(div8), 1);
    let dimension = |bits: &mut Vec<bool>, value: u32| {
        if div8 {
            put(bits, value / 8 - 1, 5);
        } else {
            put(bits, selector, 2);
            put(bits, value - 1, [9, 13, 18, 30][selector as usize]);
        }
    };
    dimension(&mut bits, height);
    put(&mut bits, ratio, 3);
    if ratio == 0 {
        dimension(&mut bits, width);
    }
    put(&mut bits, u32::from(orientation.is_none()), 1);
    if let Some(value) = orientation {
        put(&mut bits, u32::from(value != 0), 1);
        if value != 0 {
            put(&mut bits, u32::from(value - 1), 3);
        }
    }
    pack(&bits)
}
fn stored_brotli(bytes: &[u8]) -> Vec<u8> {
    assert!(!bytes.is_empty() && bytes.len() <= 65536);
    let mut bits = Vec::new();
    put(&mut bits, 0, 1);
    put(&mut bits, 0, 1);
    put(&mut bits, 0, 2);
    put(&mut bits, bytes.len() as u32 - 1, 16);
    put(&mut bits, 1, 1);
    let mut output = pack(&bits);
    output.extend(bytes);
    output.push(3);
    output
}

fn put(bits: &mut Vec<bool>, value: u32, count: usize) {
    bits.extend((0..count).map(|i| value & (1 << i) != 0));
}

fn pack(bits: &[bool]) -> Vec<u8> {
    bits.chunks(8)
        .map(|chunk| {
            chunk
                .iter()
                .enumerate()
                .fold(0, |v, (i, b)| v | (u8::from(*b) << i))
        })
        .collect()
}
