use super::common::*;
use ente_exif::{Error, Limits, Mode};
use std::io::{self, Cursor, Read, Seek, SeekFrom};

#[test]
fn io_errors_propagate_and_unknown_formats_only_read_the_header() {
    struct Failed;
    impl Read for Failed {
        fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
            Err(io::Error::other("failed source"))
        }
    }
    impl Seek for Failed {
        fn seek(&mut self, _: SeekFrom) -> io::Result<u64> {
            Ok(100)
        }
    }
    let error = ente_exif::read(&mut Failed, Mode::Summary, Limits::default()).unwrap_err();
    assert!(matches!(error, Error::Io(_)));
    let source = std::error::Error::source(&error).unwrap();
    assert!(source.is::<io::Error>());
    assert_eq!(source.to_string(), "failed source");
    let mut input = Cursor::new(vec![b'a'; 1_000_000]);
    assert!(matches!(
        ente_exif::read(&mut input, Mode::Summary, Limits::default()),
        Err(Error::Unsupported("format"))
    ));
    assert_eq!(input.position(), 16);
}

#[test]
fn xml_namespace_expansion_duplicate_attributes_and_multiple_roots() {
    let declarations: String = (0..65)
        .map(|i| format!(" xmlns:p{i}=\"urn:{i}\""))
        .collect();
    let duplicate = format!(
        "<r:RDF xmlns:r=\"{}\"><r:Description a=\"1\" a=\"2\"/></r:RDF>",
        ente_exif::namespace::RDF
    );
    for xml in [
        format!("<root{declarations}/>"),
        duplicate,
        xmp("") + "<second/>",
    ] {
        assert!(ente_exif::read(&mut Cursor::new(xml), Mode::Details, Limits::default()).is_err());
    }
}

#[test]
fn compressed_png_cannot_expand_beyond_budget() {
    let text = miniz_oxide::deflate::compress_to_vec_zlib(&vec![b'a'; 100_000], 6);
    let bytes = [
        b"\x89PNG\r\n\x1a\n".to_vec(),
        png_chunk(
            *b"zTXt",
            &[b"XML:com.adobe.xmp\0\0".to_vec(), text].concat(),
        ),
        png_chunk(*b"IEND", &[]),
    ]
    .concat();
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(bytes), Mode::Summary, Limits::default()),
        Err(Error::Limit(_))
    ));

    let packet = xmp(&" ".repeat(4000));
    let compressed = miniz_oxide::deflate::compress_to_vec_zlib(packet.as_bytes(), 6);
    let chunk = png_chunk(
        *b"zTXt",
        &[b"XML:com.adobe.xmp\0\0".to_vec(), compressed].concat(),
    );
    let mut repeated = b"\x89PNG\r\n\x1a\n".to_vec();
    for _ in 0..8 {
        repeated.extend(&chunk);
    }
    let limits = Limits {
        read_bytes: 10_000,
        ..Limits::default()
    };
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(repeated), Mode::Summary, limits),
        Err(Error::Limit("expanded bytes"))
    ));
}

#[test]
fn length_fields_and_entry_counts_do_not_drive_allocations() {
    let cases = [
        tiff(
            &[(0x10f, 2, u32::MAX, u32::MAX.to_le_bytes().to_vec())],
            false,
        ),
        [b"\x89PNG\r\n\x1a\n".as_slice(), &[0xff; 4], b"iTXt"].concat(),
        b"RIFF\xff\xff\xff\xffWEBPEXIF\xff\xff\xff\xff".to_vec(),
        [
            1u32.to_be_bytes().to_vec(),
            b"ftyp".to_vec(),
            u64::MAX.to_be_bytes().to_vec(),
        ]
        .concat(),
    ];
    for bytes in cases {
        assert!(
            ente_exif::read(&mut Cursor::new(bytes), Mode::Details, Limits::default()).is_err()
        );
    }
    let bytes = tiff(&[(0x10f, 2, 6, b"Canon\0".to_vec())], false);
    for limits in [
        Limits {
            entries: 0,
            ..Limits::default()
        },
        Limits {
            directories: 0,
            ..Limits::default()
        },
        Limits {
            read_bytes: 1,
            ..Limits::default()
        },
    ] {
        assert!(matches!(
            ente_exif::read(&mut Cursor::new(&bytes), Mode::Summary, limits),
            Err(Error::Limit(_))
        ));
    }
}

#[test]
fn oversized_jxrs_footer_does_not_read_its_payload() {
    let bytes = [
        jpeg(&[], ""),
        b"jxrs".to_vec(),
        u32::MAX.to_le_bytes().to_vec(),
    ]
    .concat();
    assert!(matches!(
        ente_exif::read(&mut Cursor::new(bytes), Mode::Summary, Limits::default()),
        Err(Error::Limit("JXRS index"))
    ));
}

#[test]
fn png_text_limits_apply_to_utf8_output_before_conversion() {
    let limits = Limits {
        value_bytes: 4,
        ..Limits::default()
    };
    for (kind, payload, expected) in [
        (b"tEXt", b"Note\0ABCD".to_vec(), Some("ABCD")),
        (b"tEXt", b"Note\0ABCDE".to_vec(), None),
        (b"tEXt", b"Note\0\xe9\xe9".to_vec(), Some("éé")),
        (b"tEXt", b"Note\0\xe9\xe9\xe9".to_vec(), None),
        (
            b"zTXt",
            [
                b"Note\0\0".to_vec(),
                miniz_oxide::deflate::compress_to_vec_zlib(b"\xe9\xe9\xe9", 6),
            ]
            .concat(),
            None,
        ),
        (b"iTXt", "Note\0\0\0\0\0éé".as_bytes().to_vec(), Some("éé")),
        (b"iTXt", "Note\0\0\0\0\0ééé".as_bytes().to_vec(), None),
    ] {
        let bytes = [
            b"\x89PNG\r\n\x1a\n".to_vec(),
            png_chunk(*b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
            png_chunk(*kind, &payload),
            png_chunk(*b"IEND", &[]),
        ]
        .concat();
        let result = ente_exif::read(&mut Cursor::new(&bytes), Mode::Details, limits);
        if let Some(expected) = expected {
            assert_eq!(
                result.unwrap().property("urn:png:text", "Note"),
                Some(expected)
            );
        } else {
            assert!(matches!(result, Err(Error::Limit("PNG text"))));
        }
        assert!(ente_exif::read(&mut Cursor::new(&bytes), Mode::Summary, limits).is_ok());
    }
}

#[test]
fn undersized_jxrs_is_recoverable() {
    for length in 0u32..8 {
        let bytes = [
            jpeg(&[], ""),
            b"jxrs".to_vec(),
            length.to_le_bytes().to_vec(),
        ]
        .concat();
        for mode in [Mode::Summary, Mode::Details] {
            let metadata = read(&bytes, mode);
            assert_eq!(metadata.width(), Some(30));
            assert_eq!(metadata.issues.len(), 1);
            assert_eq!(metadata.issues[0].message, "JXRS length");
        }
    }
}

#[test]
fn png_language_obeys_value_and_retention_budgets() {
    let bytes = [
        b"\x89PNG\r\n\x1a\n".to_vec(),
        png_chunk(*b"iTXt", b"Note\0\0\0en-US\0\0x"),
    ]
    .concat();
    for limits in [
        Limits {
            value_bytes: 4,
            ..Limits::default()
        },
        Limits {
            output_bytes: std::mem::size_of::<ente_exif::Property>()
                + "urn:png:text".len()
                + "Note".len()
                + 1
                + 4,
            ..Limits::default()
        },
    ] {
        assert!(matches!(
            ente_exif::read(&mut Cursor::new(&bytes), Mode::Details, limits),
            Err(Error::Limit(_))
        ));
    }
}
